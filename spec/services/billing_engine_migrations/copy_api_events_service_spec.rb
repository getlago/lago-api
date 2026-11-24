# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyApiEventsService, :capture_kafka_messages do
  subject(:result) { described_class.call(organization_id: organization.id, events_json: events_attributes.to_json) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization, clickhouse_events_store: true) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:, code: "legacy") }
  let_it_be(:override_plan) { create(:plan, organization:, code: "legacy", parent: plan) }

  let(:migration_status) { "shadowing" }
  let(:events_copy_source) { "api" }
  let(:events_attributes) do
    [
      event_attributes(transaction_id: "tr-1", external_subscription_id: "sub-mapped"),
      event_attributes(transaction_id: "tr-2", external_subscription_id: "sub-override"),
      event_attributes(transaction_id: "tr-3", external_subscription_id: "sub-unknown")
    ]
  end

  def event_attributes(**overrides)
    {
      external_customer_id: customer.external_id,
      code: "api_calls",
      timestamp: 1_763_900_000.123,
      precise_total_amount_cents: "12.5",
      properties: {"region" => "eu"},
      **overrides
    }
  end

  before do
    stub_const("ENV", ENV.to_h.merge("LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka", "LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC" => "product_events_raw"))

    create(:subscription, customer:, plan:, external_id: "sub-mapped")
    create(:subscription, customer:, plan: override_plan, external_id: "sub-override")
    create(
      :billing_engine_migration,
      organization:,
      shadow_organization:,
      plan_mapping: {"legacy" => "catalog"},
      status: migration_status,
      events_copy_source:
    )
  end

  it "copies the events of mapped subscriptions with their values" do
    freeze_time do
      expect(result).to be_success
      expect(result.copied_count).to eq(1)
      expect(result.unmapped_count).to eq(2)

      expect(kafka_messages.map { JSON.parse(it[:payload]) }).to eq(
        [
          {
            "organization_id" => shadow_organization.id,
            "external_customer_id" => customer.external_id,
            "external_contract_id" => "sub-mapped",
            "transaction_id" => "tr-1",
            "timestamp" => "1763900000.123",
            "code" => "api_calls",
            "precise_total_amount_cents" => "12.5",
            "properties" => {"region" => "eu"},
            "ingested_at" => Time.zone.now.iso8601(3)[...-1],
            "source" => "http_ruby",
            "source_metadata" => {"api_post_processed" => false}
          }
        ]
      )
    end
  end

  context "when the migration switched to the raw topic after the events were enqueued" do
    let(:events_copy_source) { "raw_topic" }

    it "leaves them to the raw topic copy" do
      expect(result).to be_success
      expect(result.copied_count).to be_nil
      expect(karafka_producer).not_to have_received(:produce_many_sync)
    end
  end

  context "when the migration was paused after the events were enqueued" do
    let(:migration_status) { "paused" }

    it "copies nothing" do
      expect(result).to be_success
      expect(karafka_producer).not_to have_received(:produce_many_sync)
    end
  end

  context "when the shadow organization left the ClickHouse store" do
    before { Organization.find(shadow_organization.id).update!(clickhouse_events_store: false) }

    it "fails" do
      expect { result }.to raise_error(BaseService::ServiceFailure) { expect(it.code).to eq("shadow_organization_not_on_clickhouse_events_store") }
    end
  end
end
