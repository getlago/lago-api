# frozen_string_literal: true

FactoryBot.define do
  factory :kinesis_destination, class: "StreamingDestinations::KinesisDestination" do
    organization
    type { "StreamingDestinations::KinesisDestination" }
    code { "kinesis_#{SecureRandom.uuid}" }
    name { "Kinesis destination 1" }

    transient do
      stream_arn { "arn:aws:kinesis:eu-west-1:111122223333:stream/lago" }
      region { "eu-west-1" }
      role_arn { "arn:aws:iam::111122223333:role/LagoStreamingWriter" }
      external_id { SecureRandom.uuid }
    end

    # String keys on purpose: SettingsStorable reads settings["stream_arn"], so
    # symbol keys would make every accessor nil until the record round-trips
    # through the database, and presence validation would fail on build.
    settings do
      {
        "stream_arn" => stream_arn,
        "region" => region,
        "role_arn" => role_arn,
        "external_id" => external_id
      }
    end
  end
end
