# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyEventsService, :capture_kafka_messages do
  subject(:result) { described_class.call(migration:, events:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization, refind: true) { create(:shadow_organization, clickhouse_events_store: true) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:, code: "legacy") }
  let_it_be(:unmapped_plan) { create(:plan, organization:, code: "other") }

  let(:migration) { BillingEngineMigrations::Lookup.for_source(organization.id) }
  let(:events) { [build_event(transaction_id: "tr-1"), build_event(transaction_id: "tr-2", external_subscription_id: "sub-unmapped")] }
  let(:product_topic) { "product_events_raw" }

  def build_event(**overrides)
    described_class::Event.new(
      external_customer_id: customer.external_id,
      external_subscription_id: "sub-mapped",
      transaction_id: "tr-1",
      code: "api_calls",
      timestamp: Time.zone.at(1_763_900_000.123),
      precise_total_amount_cents: BigDecimal("12.5"),
      properties: {"region" => "eu"},
      **overrides
    )
  end

  before do
    stub_const("ENV", ENV.to_h.merge("LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka", "LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC" => product_topic))

    create(:subscription, customer:, plan:, external_id: "sub-mapped")
    create(:subscription, customer:, plan: unmapped_plan, external_id: "sub-unmapped")
    create(:billing_engine_migration, organization:, shadow_organization:, plan_mapping: {"legacy" => "catalog"})
  end

  it "produces the events of mapped subscriptions for the shadow organization and waits for Kafka" do
    expect(result).to be_success
    expect(result.copied_count).to eq(1)
    expect(result.unmapped_count).to eq(1)

    expect(karafka_producer).to have_received(:produce_many_sync).once
    expect(kafka_messages.map { it[:topic] }).to eq([product_topic])
    expect(JSON.parse(kafka_messages.sole[:payload])).to include(
      "organization_id" => shadow_organization.id,
      "external_contract_id" => "sub-mapped",
      "transaction_id" => "tr-1",
      "code" => "api_calls",
      "timestamp" => "1763900000.123",
      "precise_total_amount_cents" => "12.5",
      "properties" => {"region" => "eu"}
    )
  end

  context "without an event of a mapped subscription" do
    let(:events) { [build_event(external_subscription_id: "sub-unmapped"), build_event(external_subscription_id: nil)] }

    it "produces nothing" do
      expect(result).to be_success
      expect(result.copied_count).to eq(0)
      expect(result.unmapped_count).to eq(2)
      expect(karafka_producer).not_to have_received(:produce_many_sync)
    end
  end

  context "without the product events topic" do
    let(:product_topic) { nil }

    it "fails instead of dropping the copies" do
      expect(result).to be_failure
      expect(result.error.code).to eq("product_raw_events_topic_missing")
      expect(karafka_producer).not_to have_received(:produce_many_sync)
    end
  end

  context "when the shadow organization reads its usage from PostgreSQL" do
    before { shadow_organization.update!(clickhouse_events_store: false) }

    it "fails instead of producing copies its usage would not read" do
      expect(result).to be_failure
      expect(result.error.code).to eq("shadow_organization_not_on_clickhouse_events_store")
      expect(karafka_producer).not_to have_received(:produce_many_sync)
    end
  end

  context "when Kafka refuses the copies" do
    before { allow(karafka_producer).to receive(:produce_many_sync).and_raise(WaterDrop::Errors::ProduceManyError.new([], "boom")) }

    it "raises" do
      expect { result }.to raise_error(WaterDrop::Errors::ProduceManyError)
    end
  end
end
