# frozen_string_literal: true

require "rails_helper"

RSpec.describe StreamingDestinations::Kinesis::DeliverService do
  subject(:deliver_service) { described_class.new(destination:, payload:, partition_key:) }

  let(:destination) { create(:kinesis_destination) }
  let(:partition_key) { "cust_external_id" }
  let(:payload) do
    {
      :webhook_type => "subscription.updated",
      :object_type => "subscription",
      :organization_id => destination.organization_id,
      :emitted_at => "2026-08-31T12:00:00.000Z",
      "subscription" => {lago_id: "sub_1", external_id: "cust_external_id"}
    }
  end

  let(:credentials) { instance_double(Aws::AssumeRoleCredentials) }
  let(:sts_client) { instance_double(Aws::STS::Client) }
  let(:kinesis_client) do
    Aws::Kinesis::Client.new(
      stub_responses: true,
      region: "eu-west-1",
      credentials: Aws::Credentials.new("stub", "stub")
    )
  end

  before do
    # Class-level cache, so it has to be reset or counts leak between examples.
    described_class::CREDENTIALS.clear

    # Built before the stub is installed, otherwise .new would recurse into it.
    client = kinesis_client

    allow(Aws::Kinesis::Client).to receive(:new).and_return(client)
    allow(Aws::STS::Client).to receive(:new).and_return(sts_client)
    allow(Aws::AssumeRoleCredentials).to receive(:new).and_return(credentials)
  end

  describe "#call" do
    it "puts the payload on the destination's stream" do
      result = deliver_service.call

      expect(result).to be_success

      request = kinesis_client.api_requests.first
      expect(request[:operation_name]).to eq(:put_record)
      expect(request[:params][:stream_arn]).to eq(destination.stream_arn)
      expect(request[:params][:partition_key]).to eq("cust_external_id")
      expect(JSON.parse(request[:params][:data])).to eq(
        "webhook_type" => "subscription.updated",
        "object_type" => "subscription",
        "organization_id" => destination.organization_id,
        "emitted_at" => "2026-08-31T12:00:00.000Z",
        "subscription" => {"lago_id" => "sub_1", "external_id" => "cust_external_id"}
      )
    end

    it "stringifies a non-string partition key" do
      result = described_class.new(destination:, payload:, partition_key: 42).call

      expect(result).to be_success
      expect(kinesis_client.api_requests.first[:params][:partition_key]).to eq("42")
    end

    it "builds the client for the destination's region with the assumed-role credentials" do
      deliver_service.call

      expect(Aws::Kinesis::Client).to have_received(:new).with(
        region: destination.region,
        credentials: credentials
      )
    end

    it "assumes the role with the external id as a confused-deputy guard" do
      deliver_service.call

      expect(Aws::AssumeRoleCredentials).to have_received(:new).with(
        role_arn: destination.role_arn,
        role_session_name: "lago-streaming-#{destination.id}",
        client: sts_client,
        external_id: destination.external_id
      )
    end

    context "when the destination has no external_id" do
      let(:destination) { create(:kinesis_destination, external_id: nil) }

      it "omits it rather than passing nil, which AWS rejects" do
        deliver_service.call

        expect(Aws::AssumeRoleCredentials).to have_received(:new).with(
          role_arn: destination.role_arn,
          role_session_name: "lago-streaming-#{destination.id}",
          client: sts_client
        )
      end
    end

    describe "credential caching" do
      it "does not rebuild the credentials on a second call for the same destination" do
        deliver_service.call
        described_class.new(destination:, payload:, partition_key:).call

        expect(Aws::AssumeRoleCredentials).to have_received(:new).once
      end

      it "rebuilds them for a different destination" do
        other = create(:kinesis_destination, organization: destination.organization)

        deliver_service.call
        described_class.new(destination: other, payload:, partition_key:).call

        expect(Aws::AssumeRoleCredentials).to have_received(:new).twice
      end

      it "rebuilds them when the destination's role changes" do
        deliver_service.call

        destination.role_arn = "arn:aws:iam::111122223333:role/Rotated"
        destination.save!
        described_class.new(destination:, payload:, partition_key:).call

        expect(Aws::AssumeRoleCredentials).to have_received(:new).twice
      end
    end

    context "when the serialized payload exceeds the kinesis record limit" do
      let(:payload) do
        {
          :webhook_type => "subscription.updated",
          "subscription" => {blob: "x" * (1.megabyte + 1)}
        }
      end

      before { allow(Sentry).to receive(:capture_message) }

      it "fails the result without raising and without calling kinesis" do
        result = nil

        expect { result = deliver_service.call }.not_to raise_error

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ServiceFailure)
        expect(result.error.code).to eq("record_too_large")
        expect(kinesis_client.api_requests).to be_empty
      end

      it "reports the oversized record to Sentry" do
        deliver_service.call

        expect(Sentry).to have_received(:capture_message).with(
          /exceeds the #{described_class::MAX_RECORD_SIZE} byte limit/o,
          hash_including(level: :error)
        )
      end
    end
  end
end
