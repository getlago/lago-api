# frozen_string_literal: true

FactoryBot.define do
  factory :kinesis_destination, class: "StreamingDestinations::KinesisDestination" do
    organization
    type { "StreamingDestinations::KinesisDestination" }
    event_types { ["customer_usage.refreshed"] }

    settings do
      {
        stream_arn: "arn:aws:kinesis:eu-west-1:123456789012:stream/lago-streaming-sandbox",
        region: "eu-west-1",
        role_arn: "arn:aws:iam::123456789012:role/lago-streaming-sandbox-writer",
        partition_key: "customer_external_id"
      }
    end
  end
end
