# frozen_string_literal: true

require "aws-sdk-kinesis"

module EventDestinations
  class KinesisProducer
    HTTP_OPEN_TIMEOUT = 2
    HTTP_READ_TIMEOUT = 5
    RETRY_LIMIT = 1

    ROLE_SESSION_NAME = "lago-event-destinations"

    DELIVERY_ERRORS = [
      Aws::Kinesis::Errors::ResourceNotFoundException,
      Aws::Kinesis::Errors::AccessDeniedException,
      Aws::Kinesis::Errors::ValidationException,
      Aws::Kinesis::Errors::ProvisionedThroughputExceededException,
      Aws::STS::Errors::AccessDenied,
      Aws::Errors::MissingCredentialsError,
      Seahorse::Client::NetworkingError
    ].freeze

    ASSUMED_CREDENTIALS = Concurrent::Map.new
    CLIENTS = Concurrent::Map.new

    def initialize(destination:)
      @destination = destination
    end

    def produce(data:, partition_key:)
      payload = JSON.generate(data)

      response = client.put_record(
        stream_arn: destination.stream_arn,
        data: payload,
        partition_key:
      )

      Rails.logger.info(
        "#{log_prefix} delivered partition_key=#{partition_key} bytes=#{payload.bytesize} " \
        "shard=#{response.shard_id} sequence=#{response.sequence_number}"
      )

      response
    rescue *DELIVERY_ERRORS => e
      Rails.logger.error(
        "#{log_prefix} dropped partition_key=#{partition_key} bytes=#{payload&.bytesize} " \
        "error=#{e.class} message=#{e.message}"
      )

      nil
    end

    private

    attr_reader :destination

    def log_prefix
      "[streaming] destination=#{destination.id} stream=#{destination.stream_arn}"
    end

    def client
      CLIENTS.compute_if_absent([destination.role_arn, destination.region]) do
        build_client
      end
    end

    def build_client
      Aws::Kinesis::Client.new(
        region: destination.region,
        credentials: assumed_credentials,
        **client_timeouts
      ).tap do |kinesis|
        raise Aws::Errors::MissingCredentialsError if kinesis.config.credentials.nil?
      end
    end

    def assumed_credentials
      ASSUMED_CREDENTIALS.compute_if_absent([destination.role_arn, destination.region]) do
        Aws::AssumeRoleCredentials.new(
          role_arn: destination.role_arn,
          role_session_name: ROLE_SESSION_NAME,
          client: Aws::STS::Client.new(region: destination.region, **client_timeouts)
        )
      end
    end

    def client_timeouts
      {
        http_open_timeout: HTTP_OPEN_TIMEOUT,
        http_read_timeout: HTTP_READ_TIMEOUT,
        retry_limit: RETRY_LIMIT
      }
    end
  end
end
