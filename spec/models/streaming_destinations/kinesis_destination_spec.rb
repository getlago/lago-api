# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamingDestinations::KinesisDestination, type: :model do
  subject(:destination) { create(:kinesis_destination) }

  describe "validations" do
    it do
      expect(destination).to validate_presence_of(:stream_arn)
      expect(destination).to validate_presence_of(:region)
      expect(destination).to validate_presence_of(:role_arn)
    end

    it "rejects an unsupported partition key" do
      destination = build(:kinesis_destination)
      destination.partition_key = "subscription_external_id"

      expect(destination).not_to be_valid
      expect(destination.errors.where(:partition_key, :inclusion)).to be_present
    end
  end

  describe "settings" do
    it "reads the settings back" do
      expect(destination.stream_arn).to eq("arn:aws:kinesis:eu-west-1:123456789012:stream/lago-streaming-sandbox")
      expect(destination.region).to eq("eu-west-1")
      expect(destination.role_arn).to eq("arn:aws:iam::123456789012:role/lago-streaming-sandbox-writer")
      expect(destination.partition_key).to eq("customer_external_id")
    end

    it "defaults the partition key when unset" do
      destination = build(:kinesis_destination, settings: {stream_arn: "arn", region: "eu-west-1", role_arn: "role"})

      expect(destination.partition_key).to eq(described_class::DEFAULT_PARTITION_KEY)
    end
  end
end
