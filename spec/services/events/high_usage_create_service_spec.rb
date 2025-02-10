# frozen_string_literal: true

require "rails_helper"

RSpec.describe Events::HighUsageCreateService, type: :service do
  subject(:create_service) do
    described_class.new(
      organization:,
      params:,
      timestamp: creation_timestamp
    )
  end

  let(:organization) { create(:organization) }

  let(:code) { "sum_agg" }
  let(:external_subscription_id) { SecureRandom.uuid }
  let(:timestamp) { Time.current.to_f }
  let(:transaction_id) { SecureRandom.uuid }
  let(:precise_total_amount_cents) { nil }

  let(:creation_timestamp) { Time.current.to_f }

  let(:params) do
    {
      external_subscription_id:,
      code:,
      transaction_id:,
      precise_total_amount_cents:,
      properties: {foo: "bar"},
      timestamp:
    }
  end

  describe "#call" do
    let(:karafka_producer) { instance_double(WaterDrop::Producer) }

    before do
      ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
      ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"

      allow(Karafka).to receive(:producer).and_return(karafka_producer)
      allow(karafka_producer).to receive(:produce_async)
    end

    it "produces the event on kafka" do
      travel_to(Time.current) do
        result = create_service.call
        expect(result).to be_success
        expect(result.transaction_id).to eq(transaction_id)

        expect(karafka_producer).to have_received(:produce_async)
          .with(
            topic: "raw_events",
            key: "#{organization.id}-#{external_subscription_id}",
            payload: {
              organization_id: organization.id,
              external_subscription_id:,
              transaction_id:,
              timestamp: timestamp,
              code:,
              precise_total_amount_cents: "0.0",
              properties: {foo: "bar"},
              ingested_at: Time.current.iso8601[...-1],
              source: "http_ruby_high_usage"
            }.to_json
          )
      end
    end

    context "with a precise_total_amount_cents" do
      let(:precise_total_amount_cents) { "123.45" }

      it "produces the event on kafka" do
        travel_to(Time.current) do
          result = create_service.call
          expect(result).to be_success
          expect(result.transaction_id).to eq(transaction_id)

          expect(karafka_producer).to have_received(:produce_async)
            .with(
              topic: "raw_events",
              key: "#{organization.id}-#{external_subscription_id}",
              payload: {
                organization_id: organization.id,
                external_subscription_id:,
                transaction_id:,
                timestamp: timestamp,
                code:,
                precise_total_amount_cents: "123.45",
                properties: {foo: "bar"},
                ingested_at: Time.current.iso8601[...-1],
                source: "http_ruby_high_usage"
              }.to_json
            )
        end
      end

      context "when precise_total_amount_cents is not a valid decimal value" do
        let(:precise_total_amount_cents) { "asdfa" }

        it "produces the event on kafka" do
          travel_to(Time.current) do
            result = create_service.call
            expect(result).to be_success
            expect(result.transaction_id).to eq(transaction_id)

            expect(karafka_producer).to have_received(:produce_async)
              .with(
                topic: "raw_events",
                key: "#{organization.id}-#{external_subscription_id}",
                payload: {
                  organization_id: organization.id,
                  external_subscription_id:,
                  transaction_id:,
                  timestamp: timestamp,
                  code:,
                  precise_total_amount_cents: "0.0",
                  properties: {foo: "bar"},
                  ingested_at: Time.current.iso8601[...-1],
                  source: "http_ruby_high_usage"
                }.to_json
              )
          end
        end
      end
    end

    context "when timestamp is not present in the payload" do
      let(:timestamp) { nil }

      it "produces the event on kafka" do
        result = create_service.call
        expect(result).to be_success
        expect(result.transaction_id).to eq(transaction_id)

        expect(karafka_producer).to have_received(:produce_async)
          .with(
            topic: "raw_events",
            key: "#{organization.id}-#{external_subscription_id}",
            payload: {
              organization_id: organization.id,
              external_subscription_id:,
              transaction_id:,
              timestamp: creation_timestamp.to_i,
              code:,
              precise_total_amount_cents: "0.0",
              properties: {foo: "bar"},
              ingested_at: Time.current.iso8601[...-1],
              source: "http_ruby_high_usage"
            }.to_json
          )
      end
    end
  end
end
