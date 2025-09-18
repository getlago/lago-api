# frozen_string_literal: true

RSpec.describe Utils::ApiLog do
  subject(:api_log) { described_class }

  let(:api_key) { create(:api_key) }

  let(:fake_request) do
    instance_double(
      "ActionDispatch::Request",
      user_agent: "RSpec",
      params: {parameters: [1, 2, 3, 4]},
      path: "/api/v1/customers",
      base_url: "https://lago.test",
      method_symbol: :post
    )
  end

  let(:fake_response) do
    instance_double(
      "ActionDispatch::Response",
      status: 200,
      body: {"success" => true}.to_json
    )
  end

  before do
    allow(CurrentContext).to receive(:api_key_id).and_return(api_key.id)
    travel_to(Time.zone.parse("2023-03-22 12:00:00"))
  end

  describe ".produce" do
    let(:organization) { create(:organization) }
    let(:karafka_producer) { instance_double(WaterDrop::Producer) }

    before do
      allow(Karafka).to receive(:producer).and_return(karafka_producer)
      allow(karafka_producer).to receive(:produce_async)
    end

    context "when kafka is configured" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = "api_logs"
      end

      after do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = nil
      end

      it "produces the event on kafka" do
        api_log.produce(fake_request, fake_response, organization:, request_id: "1234")

        expect(karafka_producer).to have_received(:produce_async).with(
          topic: "api_logs",
          key: "#{organization.id}--1234",
          payload: {
            request_id: "1234",
            organization_id: organization.id,
            api_key_id: api_key.id,
            api_version: "v1",
            client: "RSpec",
            request_body: {parameters: [1, 2, 3, 4]},
            request_path: "/api/v1/customers",
            request_origin: "https://lago.test",
            http_method: :post,
            request_response: {"success" => true},
            http_status: 200,
            logged_at: Time.current.iso8601[...-1],
            created_at: Time.current.iso8601[...-1]
          }.to_json
        )
      end
    end

    context "when kafka is not configured" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = nil
      end

      it "does not produce message" do
        api_log.produce(fake_request, fake_response, organization:)
        expect(karafka_producer).not_to have_received(:produce_async)
      end
    end

    describe ".available?" do
      subject { api_log.available? }

      context "without clickhouse" do
        before do
          ENV["LAGO_CLICKHOUSE_ENABLED"] = nil
        end

        it { is_expected.to be_falsey }
      end

      context "without kafka vars" do
        before do
          ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
          ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = nil
          ENV["LAGO_CLICKHOUSE_ENABLED"] = "true"
        end

        it { is_expected.to be_falsey }
      end

      context "with everything configured" do
        before do
          ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
          ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = "api_logs"
          ENV["LAGO_CLICKHOUSE_ENABLED"] = "true"
        end

        after do
          ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
          ENV["LAGO_KAFKA_API_LOGS_TOPIC"] = nil
        end

        it { is_expected.to be_truthy }
      end
    end
  end
end
