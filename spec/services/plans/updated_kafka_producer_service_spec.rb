# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::UpdatedKafkaProducerService do
  subject(:producer_service) do
    described_class.new(
      plan:,
      resources_type: "charge",
      resources_ids: [resource.id],
      event_type:,
      timestamp:
    )
  end

  let(:organization) { create(:organization, premium_integrations:) }
  let(:plan) { create(:plan, organization:) }
  let(:resource) { create(:standard_charge, plan:, organization:) }
  let(:event_type) { "charge.deleted" }
  let(:timestamp) { Time.current }

  let(:premium_integrations) { [] }
  let(:karafka_producer) { instance_double(WaterDrop::Producer) }

  describe "#call" do
    before do
      allow(Karafka).to receive(:producer).and_return(karafka_producer)
      allow(karafka_producer).to receive(:produce_async)
    end

    context "with Kafka config", :premium do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka"
        ENV["LAGO_KAFKA_PLAN_CONFIG_UPDATED_TOPIC"] = "plan_config_updated"
      end

      let(:premium_integrations) { ["clickhouse_live_aggregation"] }

      it "produces the message on kafka" do
        freeze_time do
          producer_service.call

          expect(karafka_producer).to have_received(:produce_async)
            .with(
              topic: "plan_config_updated",
              key: "#{organization.id}-#{plan.id}",
              payload: {
                organization_id: organization.id,
                plan_id: plan.id,
                resources_type: "charge",
                resources_ids: [resource.id],
                event_type:,
                timestamp: timestamp.iso8601(3),
                produced_at: Time.current.iso8601
              }
            )
        end
      end

      context "when the clickhouse live aggregation is not enabled" do
        let(:premium_integrations) { [] }

        it "does not produce the message on kafka" do
          freeze_time do
            producer_service.call

            expect(karafka_producer).not_to have_received(:produce_async)
          end
        end
      end
    end

    context "without kafka config" do
      before do
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_PLAN_CONFIG_UPDATED_TOPIC"] = nil
      end

      it "does not produce the event on kafka" do
        freeze_time do
          producer_service.call

          expect(karafka_producer).not_to have_received(:produce_async)
        end
      end
    end
  end
end
