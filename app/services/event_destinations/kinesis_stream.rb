# frozen_string_literal: true

module EventDestinations
  # POC stand-in for the future per-organization destination record: the target stream is
  # described by ENV instead of a persisted row.
  class KinesisStream
    LIVE_TRANSPORT = "kinesis"

    def self.for(organization)
      return nil if ENV["LAGO_EVENT_DESTINATION_ORG_ID"].blank?
      return nil unless organization&.id == ENV["LAGO_EVENT_DESTINATION_ORG_ID"]

      new
    end

    def stream_arn = ENV.fetch("LAGO_EVENT_DESTINATION_KINESIS_STREAM_ARN")

    def region = ENV.fetch("LAGO_EVENT_DESTINATION_KINESIS_REGION")

    # Only an explicit "kinesis" opts into real delivery: unset, blank or unrecognized
    # values must never silently start writing to a live stream.
    def log_only?
      transport = ENV["LAGO_EVENT_DESTINATION_TRANSPORT"]
      return false if transport == LIVE_TRANSPORT

      if transport.present?
        Rails.logger.warn(
          "[event_destinations] unrecognized LAGO_EVENT_DESTINATION_TRANSPORT=#{transport.inspect}, falling back to log-only"
        )
      end

      true
    end
  end
end
