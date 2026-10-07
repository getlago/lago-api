# frozen_string_literal: true

RSpec.describe Events::KafkaProducerService, :capture_kafka_messages do
  subject(:producer_service) { described_class.new(events:, organization:) }

  let(:events) { create_list(:event, 2, organization:) }
  let(:organization) { create(:organization) }

  describe "#call" do
    context "with Kafka config" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"
      end

      it "produces all events on kafka in bulk" do
        freeze_time do
          producer_service.call

          expect(karafka_producer).to have_received(:produce_many_async) do |messages|
            expect(messages.size).to eq(2)

            events.each_with_index do |event, index|
              expect(messages[index]).not_to have_key(:key)

              expect(messages[index]).to eq(
                topic: "raw_events",
                payload: {
                  organization_id: organization.id,
                  external_customer_id: event.external_customer_id,
                  external_subscription_id: event.external_subscription_id,
                  transaction_id: event.transaction_id,
                  timestamp: event.timestamp.to_f.to_s,
                  code: event.code,
                  precise_total_amount_cents: event.precise_total_amount_cents.present? ? event.precise_total_amount_cents.to_s : "0.0",
                  properties: event.properties,
                  ingested_at: Time.zone.now.iso8601(3)[...-1],
                  source: "http_ruby",
                  source_metadata: {
                    api_post_processed: true
                  }
                }.to_json
              )
            end
          end
        end
      end

      context "with a single event" do
        let(:events) { create(:event, organization:) }

        it "wraps the single event in an array and produces it" do
          producer_service.call

          expect(karafka_producer).to have_received(:produce_many_async) do |messages|
            expect(messages.size).to eq(1)
          end
        end
      end

      context "when the organization uses the product catalog" do
        let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }

        context "with the catalog topic configured" do
          before { ENV["LAGO_KAFKA_CATALOG_RAW_EVENTS_TOPIC"] = "catalog_events_raw" }
          after { ENV["LAGO_KAFKA_CATALOG_RAW_EVENTS_TOPIC"] = nil }

          it "produces the events on the catalog topic" do
            producer_service.call

            expect(karafka_producer).to have_received(:produce_many_async) do |messages|
              expect(messages.map { it[:topic] }).to eq(%w[catalog_events_raw catalog_events_raw])
            end
          end

          it "keys the payload by contract" do
            producer_service.call

            expect(karafka_producer).to have_received(:produce_many_async) do |messages|
              payloads = messages.map { JSON.parse(it[:payload]) }
              expect(payloads.map { it["external_contract_id"] }).to eq(events.map(&:external_subscription_id))
              expect(payloads.flat_map(&:keys)).not_to include("external_subscription_id")
            end
          end
        end

        context "without the catalog topic configured" do
          before { ENV["LAGO_KAFKA_CATALOG_RAW_EVENTS_TOPIC"] = nil }

          it "falls back to the raw events topic with the legacy payload" do
            producer_service.call

            expect(karafka_producer).to have_received(:produce_many_async) do |messages|
              expect(messages.map { it[:topic] }).to eq(%w[raw_events raw_events])
              expect(messages.map { JSON.parse(it[:payload])["external_subscription_id"] }).to eq(events.map(&:external_subscription_id))
            end
          end
        end
      end

      context "when the catalog topic is configured but the organization does not use the product catalog" do
        before { ENV["LAGO_KAFKA_CATALOG_RAW_EVENTS_TOPIC"] = "catalog_events_raw" }
        after { ENV["LAGO_KAFKA_CATALOG_RAW_EVENTS_TOPIC"] = nil }

        it "produces the events on the raw events topic" do
          producer_service.call

          expect(karafka_producer).to have_received(:produce_many_async) do |messages|
            expect(messages.map { it[:topic] }).to eq(%w[raw_events raw_events])
          end
        end
      end
    end

    context "without Kafka config" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
      end

      it "does not produce events on kafka" do
        producer_service.call

        expect(karafka_producer).not_to have_received(:produce_many_async)
      end
    end
  end
end
