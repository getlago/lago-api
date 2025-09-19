# frozen_string_literal: true

RSpec.describe Events::KafkaProducerService do
  subject(:producer_service) { described_class.new(event: event, organization: organization) }

  let(:event) { create(:event, organization:) }
  let(:organization) { create(:organization) }

  let(:karafka_producer) { instance_double(WaterDrop::Producer) }

  describe "#call" do
    before do
      allow(Karafka).to receive(:producer).and_return(karafka_producer)
      allow(karafka_producer).to receive(:produce_async)
    end

    context "with Kafka config" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "raw_events"
      end

      it "produces the event on kafka" do
        freeze_time do
          allow(Karafka).to receive(:producer).and_return(karafka_producer)
          allow(karafka_producer).to receive(:produce_async)

          producer_service.call

          expect(karafka_producer).to have_received(:produce_async)
            .with(
              topic: "raw_events",
              key: "#{organization.id}-#{event.external_subscription_id}",
              payload: {
                organization_id: organization.id,
                external_customer_id: event.external_customer_id,
                external_subscription_id: event.external_subscription_id,
                transaction_id: event.transaction_id,
                timestamp: event.timestamp.to_f.to_s,
                code: event.code,
                precise_total_amount_cents: event.precise_total_amount_cents.present? ? event.precise_total_amount_cents.to_s : "0.0",
                properties: event.properties,
                ingested_at: Time.zone.now.iso8601[...-1],
                source: "http_ruby",
                source_metadata: {
                  api_post_processed: true
                }
              }.to_json
            )
        end
      end
    end

    context "without" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
      end

      it "produces the event on kafka" do
        freeze_time do
          producer_service.call

          expect(karafka_producer).not_to have_received(:produce_async)
        end
      end
    end
  end
end
