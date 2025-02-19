# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V2::EventsController, type: :request do
  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:metric) { create(:billable_metric, organization:) }
  let(:plan) { create(:plan, organization:) }
  let!(:subscription) { create(:subscription, customer:, organization:, plan:, started_at: 1.month.ago) }

  describe "POST /api/v2/events" do
    subject do
      post_with_token(organization, "/api/v2/events", event: create_params)
    end

    let(:create_params) do
      {
        code: metric.code,
        transaction_id: SecureRandom.uuid,
        external_subscription_id: subscription.external_id,
        timestamp: Time.current.to_i,
        precise_total_amount_cents: "123.45",
        properties: {
          foo: "bar"
        }
      }
    end

    include_examples "requires API permission", "event", "write"

    context "without kafka configuration" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
      end

      it "returns a not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("missing_configuration")
      end
    end

    context "with kafka configuration" do
      let(:karafka_producer) { instance_double(WaterDrop::Producer) }

      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"

        allow(Karafka).to receive(:producer).and_return(karafka_producer)
        allow(karafka_producer).to receive(:produce_sync)
      end

      it "returns a success" do
        subject

        expect(response).to have_http_status(:success)
        expect(json[:event][:transaction_id]).to eq(create_params[:transaction_id])
      end
    end
  end

  describe "POST /api/v2/events/batch" do
    subject do
      post_with_token(organization, "/api/v2/events/batch", events: batch_params)
    end

    let(:batch_params) do
      [
        {
          code: metric.code,
          transaction_id: SecureRandom.uuid,
          external_subscription_id: subscription.external_id,
          timestamp: Time.current.to_i,
          precise_total_amount_cents: "123.45",
          properties: {
            foo: "bar"
          }
        }
      ]
    end

    include_examples "requires API permission", "event", "write"

    context "without kafka configuration" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
      end

      it "returns a not allowed error" do
        subject

        expect(response).to have_http_status(:method_not_allowed)
        expect(json[:code]).to eq("missing_configuration")
      end
    end

    context "with kafka configuration" do
      let(:karafka_producer) { instance_double(WaterDrop::Producer) }

      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"

        allow(Karafka).to receive(:producer).and_return(karafka_producer)
        allow(karafka_producer).to receive(:produce_many_sync)
      end

      it "returns a success" do
        subject

        expect(response).to have_http_status(:ok)
        expect(json[:events].first[:transaction_id]).to eq(batch_params.first[:transaction_id])
      end
    end
  end
end
