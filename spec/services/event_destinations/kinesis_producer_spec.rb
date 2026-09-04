# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventDestinations::KinesisProducer do
  subject(:producer) { described_class.new(destination:) }

  let(:destination) { create(:kinesis_destination) }
  let(:client) { producer.send(:client) }

  before do
    described_class::CLIENTS.clear
    described_class::ASSUMED_CREDENTIALS.clear
    Aws.config[:kinesis] = {stub_responses: true}
    Aws.config[:sts] = {stub_responses: true, credentials: Aws::Credentials.new("akid", "secret")}
  end

  after do
    Aws.config.delete(:kinesis)
    Aws.config.delete(:sts)
  end

  describe "#produce" do
    it "puts the record on the destination's stream" do
      allow(client).to receive(:put_record).and_call_original

      producer.produce(data: {hello: "world"}, partition_key: "cust_1")

      expect(client).to have_received(:put_record).with(
        stream_arn: destination.stream_arn,
        data: '{"hello":"world"}',
        partition_key: "cust_1"
      )
    end

    it "logs the shard and sequence number a landed record came back with" do
      client.stub_responses(:put_record, shard_id: "shardId-000000000000", sequence_number: "4966")
      allow(Rails.logger).to receive(:info)

      producer.produce(data: {hello: "world"}, partition_key: "cust_1")

      expect(Rails.logger).to have_received(:info).with(
        a_string_matching(
          /outcome=delivered destination_id=#{destination.id} organization_id=#{destination.organization_id} .*partition_key=cust_1 bytes=17 shard=shardId-000000000000 sequence=4966/
        )
      )
    end

    described_class::DELIVERY_ERRORS.each do |error_class|
      it "logs and returns nil on #{error_class}" do
        allow(client).to receive(:put_record).and_raise(build_aws_error(error_class))
        allow(Rails.logger).to receive(:error)

        outcome = described_class::THROTTLE_ERRORS.include?(error_class) ? "throttled" : "dropped"

        expect(producer.produce(data: {hello: "world"}, partition_key: "cust_1")).to be_nil
        expect(Rails.logger).to have_received(:error)
          .with(a_string_matching(/outcome=#{outcome} .*error=#{Regexp.escape(error_class.name)}/))
      end
    end

    it "separates a throttle from a configuration fault" do
      allow(client).to receive(:put_record)
        .and_raise(Aws::Kinesis::Errors::ProvisionedThroughputExceededException.new(nil, "slow down"))
      allow(Rails.logger).to receive(:error)

      producer.produce(data: {hello: "world"}, partition_key: "cust_1")

      expect(Rails.logger).to have_received(:error).with(a_string_matching(/outcome=throttled/))
    end

    it "does not swallow an error that is not a delivery failure" do
      allow(client).to receive(:put_record).and_raise(ArgumentError, "boom")

      expect { producer.produce(data: {hello: "world"}, partition_key: "cust_1") }.to raise_error(ArgumentError)
    end
  end

  describe "timeouts" do
    it "caps both the Kinesis and the STS client, so a hanging endpoint cannot hold a worker" do
      allow(Aws::STS::Client).to receive(:new).and_call_original

      expect(client.config.http_open_timeout).to eq(described_class::HTTP_OPEN_TIMEOUT)
      expect(client.config.http_read_timeout).to eq(described_class::HTTP_READ_TIMEOUT)
      expect(client.config.retry_limit).to eq(described_class::RETRY_LIMIT)
      expect(Aws::STS::Client).to have_received(:new).with(
        hash_including(
          http_open_timeout: described_class::HTTP_OPEN_TIMEOUT,
          http_read_timeout: described_class::HTTP_READ_TIMEOUT,
          retry_limit: described_class::RETRY_LIMIT
        )
      )
    end
  end

  describe "assumed credentials" do
    before { allow(Aws::AssumeRoleCredentials).to receive(:new).and_call_original }

    it "assumes the role once per process rather than once per delivery" do
      producer.produce(data: {hello: "world"}, partition_key: "cust_1")
      described_class.new(destination:).produce(data: {hello: "world"}, partition_key: "cust_2")

      expect(Aws::AssumeRoleCredentials).to have_received(:new).once
      expect(Aws::AssumeRoleCredentials).to have_received(:new).with(
        hash_including(role_arn: destination.role_arn, role_session_name: described_class::ROLE_SESSION_NAME)
      )
    end

    it "never shares credentials between destinations with different role ARNs" do
      other = create(:kinesis_destination)
      other.role_arn = "arn:aws:iam::210987654321:role/other-writer"
      other.save!

      producer.produce(data: {hello: "world"}, partition_key: "cust_1")
      described_class.new(destination: other).produce(data: {hello: "world"}, partition_key: "cust_2")

      expect(Aws::AssumeRoleCredentials).to have_received(:new).twice
    end
  end

  describe "credential resolution" do
    it "raises a named error rather than failing later in endpoint construction" do
      credential_less = Data.define(:credentials).new(credentials: nil)
      allow(Aws::Kinesis::Client).to receive(:new)
        .and_return(instance_double(Aws::Kinesis::Client, config: credential_less))

      expect { producer.send(:client) }.to raise_error(Aws::Errors::MissingCredentialsError)
    end
  end

  def build_aws_error(error_class)
    return error_class.new(SocketError.new("unreachable")) if error_class == Seahorse::Client::NetworkingError
    return error_class.new("test") if error_class == Aws::Errors::MissingCredentialsError

    error_class.new(nil, "test")
  end
end
