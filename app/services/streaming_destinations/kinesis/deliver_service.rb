# frozen_string_literal: true

require "aws-sdk-kinesis"

module StreamingDestinations
  module Kinesis
    class DeliverService < BaseService
      # Kinesis hard-rejects a record whose data blob exceeds 1 MiB.
      MAX_RECORD_SIZE = 1.megabyte

      # One STS AssumeRole per destination rather than per record. A fresh
      # Aws::AssumeRoleCredentials for every job would mean one STS call per
      # record, which hits STS throttling long before Kinesis notices any load.
      # The credentials object refreshes itself before expiry, so caching it is
      # safe; memoizing inside a service instance would not help, as each job
      # builds a new one.
      #
      # Keyed on the settings that shape the AssumeRole call, not on the id
      # alone, so editing a destination's role stops serving the old identity.
      CREDENTIALS = Concurrent::Map.new

      class << self
        def credentials_for(destination)
          key = [
            destination.id,
            destination.role_arn,
            destination.external_id,
            destination.region
          ].join("|")

          CREDENTIALS.compute_if_absent(key) { build_credentials(destination) }
        end

        private

        def build_credentials(destination)
          params = {
            role_arn: destination.role_arn,
            # AWS caps this at 64 characters: 15 + a 36 character uuid fits.
            role_session_name: "lago-streaming-#{destination.id}",
            client: ::Aws::STS::Client.new(region: destination.region)
          }
          # Absent unless the customer asked for one; AWS rejects a nil.
          params[:external_id] = destination.external_id if destination.external_id.present?

          ::Aws::AssumeRoleCredentials.new(**params)
        end
      end

      def initialize(destination:, payload:, partition_key:)
        @destination = destination
        @payload = payload
        @partition_key = partition_key

        super
      end

      def call
        data = payload.to_json
        return oversized_record_failure(data.bytesize) if data.bytesize > MAX_RECORD_SIZE

        client.put_record(
          stream_arn: destination.stream_arn,
          partition_key: partition_key.to_s,
          data:
        )

        result
      end

      private

      attr_reader :destination, :payload, :partition_key

      def client
        ::Aws::Kinesis::Client.new(
          region: destination.region,
          credentials: self.class.credentials_for(destination)
        )
      end

      # Kinesis rejects the record outright, so retrying cannot help and raising
      # would only burn the queue. Report it and fail the result instead.
      def oversized_record_failure(size)
        message = "Kinesis record of #{size} bytes exceeds the #{MAX_RECORD_SIZE} byte limit"

        Sentry.capture_message(
          message,
          level: :error,
          extra: {
            streaming_destination_id: destination.id,
            webhook_type: payload[:webhook_type],
            size:
          }
        )

        result.service_failure!(code: "record_too_large", message:)
      end
    end
  end
end
