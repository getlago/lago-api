# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::KinesisProducer do
  subject(:producer) { described_class.new(stream:) }

  let(:stream_arn) { "arn:aws:kinesis:eu-west-1:123456789012:stream/usage" }
  let(:log_only) { true }
  let(:stream) do
    instance_double(EventDestinations::KinesisStream, stream_arn:, region: "eu-west-1", log_only?: log_only)
  end

  describe "#produce" do
    let(:aws_client) { Aws::Kinesis::Client.new(region: "eu-west-1", stub_responses: true) }

    before do
      allow(Aws::Kinesis::Client).to receive(:new).and_return(aws_client)
      allow(aws_client).to receive(:put_record).and_call_original
    end

    it "puts the record on the configured stream" do
      producer.produce(data: {a: 1}, partition_key: "cust_1")

      expect(aws_client).to have_received(:put_record)
        .with(stream_arn:, data: '{"a":1}', partition_key: "cust_1")
    end

    it "logs the record in log mode" do
      allow(Rails.logger).to receive(:info)

      producer.produce(data: {a: 1}, partition_key: "cust_1")

      expect(Rails.logger).to have_received(:info).with(/\[event_destinations\] put_record .* bytes=7 /)
    end

    context "when the transport is live" do
      let(:log_only) { false }

      # Nobody can read a customer's stream, so the shard and sequence number are the only
      # evidence a record landed. They replace the payload rather than accompanying it.
      it "logs the shard and sequence number instead of the payload" do
        allow(Rails.logger).to receive(:info)

        producer.produce(data: {a: 1}, partition_key: "cust_1")

        expect(Rails.logger).to have_received(:info).with(/shard=ShardId sequence=SequenceNumber\z/)
      end

      it "does not log the payload" do
        allow(Rails.logger).to receive(:info)

        producer.produce(data: {a: 1}, partition_key: "cust_1")

        expect(Rails.logger).not_to have_received(:info).with(/data=/)
      end
    end
  end

  describe "client configuration" do
    before { allow(Aws::Kinesis::Client).to receive(:new).and_call_original }

    # The SDK defaults (15s connect, 60s read, 3 retries) allow ~240s per record, which would
    # hold a Sidekiq thread for minutes when the destination is unreachable.
    it "bounds the time a dead destination can cost" do
      producer.produce(data: {a: 1}, partition_key: "cust_1")

      expect(Aws::Kinesis::Client).to have_received(:new).with(
        hash_including(http_open_timeout: 2, http_read_timeout: 5, retry_limit: 1)
      )
    end

    context "when credentials cannot be resolved" do
      let(:log_only) { false }
      let(:unauthenticated) { Aws::Kinesis::Client.new(region: "eu-west-1", stub_responses: true) }

      before do
        allow(Aws::Kinesis::Client).to receive(:new).and_return(unauthenticated)
        allow(unauthenticated.config).to receive(:credentials).and_return(nil)
      end

      # Without this guard the SDK fails inside endpoint construction with
      # `NoMethodError: undefined method 'credentials' for nil`.
      it "raises a credentials error rather than a NoMethodError" do
        expect { producer.produce(data: {a: 1}, partition_key: "cust_1") }
          .to raise_error(Aws::Errors::MissingCredentialsError)
      end
    end
  end
end
