# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::HighUsageBatchCreateService, type: :service do
  subject(:create_batch_service) do
    described_class.new(
      organization:,
      params: events_params,
      timestamp: creation_timestamp
    )
  end

  let(:organization) { create(:organization) }

  let(:timestamp) { Time.current.to_f }
  let(:code) { "sum_agg" }
  let(:metadata) { {} }
  let(:creation_timestamp) { Time.current.to_f }
  let(:precise_total_amount_cents) { "123.34" }

  let(:events_params) do
    events = []
    100.times do
      event = {
        external_customer_id: SecureRandom.uuid,
        external_subscription_id: SecureRandom.uuid,
        code:,
        transaction_id: SecureRandom.uuid,
        precise_total_amount_cents:,
        properties: {foo: "bar"},
        timestamp:
      }

      events << event
    end
    events
  end

  describe ".call" do
    let(:karafka_producer) { instance_double(WaterDrop::Producer) }

    before do
      ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
      ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"

      allow(Karafka).to receive(:producer).and_return(karafka_producer)
      allow(karafka_producer).to receive(:produce_many_sync)
    end

    after do
      ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
      ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
    end

    it "produces the event on kafka" do
      expect(create_batch_service.call).to be_success

      expect(karafka_producer).to have_received(:produce_many_sync).once
    end

    context "when no events are provided" do
      let(:events_params) { [] }

      it "returns a no_events error" do
        result = nil

        aggregate_failures do
          expect { result = create_batch_service.call }.not_to change(Event, :count)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:events)
          expect(result.error.messages[:events]).to include("no_events")
        end
      end
    end

    context "when events count is too big" do
      before do
        events_params.push(
          {
            external_customer_id: SecureRandom.uuid,
            external_subscription_id: SecureRandom.uuid,
            code:,
            transaction_id: SecureRandom.uuid,
            properties: {foo: "bar"},
            timestamp:
          }
        )
      end

      it "returns a too big error" do
        result = nil

        aggregate_failures do
          expect { result = create_batch_service.call }.not_to change(Event, :count)

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages.keys).to include(:events)
          expect(result.error.messages[:events]).to include("too_many_events")
        end
      end
    end

    context "when timestamp is not present in the payload" do
      let(:timestamp) { nil }

      let(:events_params) do
        [
          {
            external_customer_id: SecureRandom.uuid,
            external_subscription_id: SecureRandom.uuid,
            code:,
            transaction_id: SecureRandom.uuid,
            properties: {foo: "bar"},
            timestamp:
          }
        ]
      end

      it "creates an event by setting the timestamp to the current datetime" do
        travel_to(Time.current) do
          result = create_batch_service.call
          expect(result).to be_success
          expect(result.transactions).to eq([{transaction_id: events_params.first[:transaction_id]}])

          params = events_params.first

          expect(karafka_producer).to have_received(:produce_many_sync)
            .with(
              [{
                topic: "raw_events",
                key: "#{organization.id}-#{params[:external_subscription_id]}",
                payload: {
                  organization_id: organization.id,
                  external_subscription_id: params[:external_subscription_id],
                  transaction_id: params[:transaction_id],
                  timestamp: creation_timestamp.to_i,
                  code: params[:code],
                  precise_total_amount_cents: "0.0",
                  properties: {foo: "bar"},
                  ingested_at: Time.current.iso8601[...-1],
                  source: "http_ruby_high_usage"
                }.to_json
              }]
            )
        end
      end
    end
  end
end
