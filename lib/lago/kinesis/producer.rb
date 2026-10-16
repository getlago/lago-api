# frozen_string_literal: true

require "aws-sdk-kinesis"

module Lago
  module Kinesis
    class Producer
      HTTP_OPEN_TIMEOUT = 2
      HTTP_READ_TIMEOUT = 5
      MAX_ATTEMPTS = 2

      ROLE_SESSION_NAME = "lago-event-destinations"
      INTERMEDIATE_SESSION_NAME = "lago-streaming-intermediate"

      # Set on a worker whose own Pod Identity role is not the principal the
      # destination trusts. It assumes this role first, then the destination.
      INTERMEDIATE_ROLE_ARN = ENV["LAGO_STREAMING_INTERMEDIATE_ROLE_ARN"].presence

      CLIENT_TIMEOUTS = {
        http_open_timeout: HTTP_OPEN_TIMEOUT,
        http_read_timeout: HTTP_READ_TIMEOUT,
        retry_mode: "standard",
        max_attempts: MAX_ATTEMPTS
      }.freeze

      THROTTLE_ERRORS = [
        Aws::Kinesis::Errors::ProvisionedThroughputExceededException
      ].freeze

      DELIVERY_ERRORS = [
        Aws::Kinesis::Errors::ResourceNotFoundException,
        Aws::Kinesis::Errors::AccessDeniedException,
        Aws::Kinesis::Errors::ValidationException,
        Aws::Kinesis::Errors::InvalidArgumentException,
        *THROTTLE_ERRORS,
        Aws::STS::Errors::AccessDenied,
        Aws::Errors::MissingCredentialsError,
        Seahorse::Client::NetworkingError
      ].freeze

      # An identity problem, as opposed to a transport or configuration one: this process cannot
      # reach that destination at all, and retrying it costs a full STS timeout each time.
      CREDENTIALS_ERRORS = [
        Aws::STS::Errors::AccessDenied,
        Aws::Errors::MissingCredentialsError
      ].freeze

      ASSUMED_CREDENTIALS = Concurrent::Map.new
      CLIENTS = Concurrent::Map.new
      UNAVAILABLE_CREDENTIALS = Concurrent::Map.new
      INTERMEDIATE_CREDENTIALS = Concurrent::Map.new

      class << self
        # Whether this process has already failed to obtain credentials for that destination.
        # Callers with somewhere else to send the work use it to stop paying the timeout.
        def credentials_available?(destination)
          !UNAVAILABLE_CREDENTIALS[credentials_key(destination)]
        end

        def credentials_key(destination)
          [destination.role_arn, destination.region, destination.external_id]
        end

        # Hop 1. Shared by every destination in a region, so it is cached apart
        # from the per-destination credentials.
        def intermediate_credentials(region)
          INTERMEDIATE_CREDENTIALS.compute_if_absent(region) do
            Aws::AssumeRoleCredentials.new(
              role_arn: INTERMEDIATE_ROLE_ARN,
              role_session_name: INTERMEDIATE_SESSION_NAME,
              client: Aws::STS::Client.new(region:, **CLIENT_TIMEOUTS)
            )
          end
        end
      end

      def initialize(destination:)
        @destination = destination
      end

      def produce(data:, partition_key:)
        payload = JSON.generate(data)

        started_at = Time.current

        response = client.put_record(
          stream_arn: destination.stream_arn,
          data: payload,
          partition_key:
        )

        log(
          :delivered,
          partition_key:,
          bytes: payload.bytesize,
          shard: response.shard_id,
          sequence: response.sequence_number,
          duration_ms: duration_ms(started_at)
        )

        response
      rescue *DELIVERY_ERRORS => e
        UNAVAILABLE_CREDENTIALS[credentials_key] = true if CREDENTIALS_ERRORS.any? { e.is_a?(it) }

        log(
          outcome_for(e),
          partition_key:,
          bytes: payload&.bytesize,
          duration_ms: duration_ms(started_at),
          error: e.class,
          message: e.message
        )

        nil
      end

      private

      attr_reader :destination

      def outcome_for(error)
        return :throttled if THROTTLE_ERRORS.any? { error.is_a?(it) }

        :dropped
      end

      def log(outcome, **fields)
        EventDestinations::DeliveryLogger.emit(outcome, destination:, stream: destination.stream_arn, **fields)
      end

      def duration_ms(started_at)
        ((Time.current - started_at) * 1000).round
      end

      def client
        CLIENTS.compute_if_absent(credentials_key) do
          build_client
        end
      end

      def build_client
        Aws::Kinesis::Client.new(
          region: destination.region,
          credentials: assumed_credentials,
          **CLIENT_TIMEOUTS
        ).tap do |kinesis|
          raise Aws::Errors::MissingCredentialsError if kinesis.config.credentials.nil?
        end
      end

      def assumed_credentials
        ASSUMED_CREDENTIALS.compute_if_absent(credentials_key) do
          Aws::AssumeRoleCredentials.new(
            role_arn: destination.role_arn,
            role_session_name: ROLE_SESSION_NAME,
            client: sts_client,
            **external_id_option
          )
        end
      end

      def sts_client
        Aws::STS::Client.new(region: destination.region, **intermediate_option, **CLIENT_TIMEOUTS)
      end

      def intermediate_option
        return {} if INTERMEDIATE_ROLE_ARN.nil?

        {credentials: self.class.intermediate_credentials(destination.region)}
      end

      def credentials_key
        self.class.credentials_key(destination)
      end

      def external_id_option
        return {} if destination.external_id.blank?

        {external_id: destination.external_id}
      end
    end
  end
end
