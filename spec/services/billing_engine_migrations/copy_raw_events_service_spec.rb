# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEngineMigrations::CopyRawEventsService, :capture_kafka_messages do
  subject(:result) { described_class.call(migrations:, raw_payloads:) }

  let_it_be(:organization) { create(:organization) }
  let_it_be(:shadow_organization) { create(:shadow_organization, clickhouse_events_store: true) }
  let_it_be(:other_organization) { create(:organization) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:plan) { create(:plan, organization:, code: "legacy") }
  let_it_be(:unmapped_plan) { create(:plan, organization:, code: "other") }

  let(:migrations) { BillingEngineMigrations::Lookup.copying_events_from("raw_topic") }
  let(:raw_payloads) { [raw_event] }
  let(:product_topic) { "product_events_raw" }

  def raw_event(**overrides)
    {
      organization_id: organization.id,
      external_customer_id: customer.external_id,
      external_subscription_id: "sub-mapped",
      transaction_id: "tr-1",
      code: "api_calls",
      timestamp: "1763900000.123",
      precise_total_amount_cents: "12.5",
      properties: {"region" => "eu"},
      source: "kinesis",
      ingested_at: "2025-11-23T12:00:00.000"
    }.merge(overrides).to_json
  end

  def copied_payloads
    kafka_messages.map { JSON.parse(it[:payload]) }
  end

  before do
    stub_const("ENV", ENV.to_h.merge("LAGO_KAFKA_BOOTSTRAP_SERVERS" => "kafka", "LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC" => product_topic))

    create(:subscription, customer:, plan:, external_id: "sub-mapped")
    create(:subscription, customer:, plan: unmapped_plan, external_id: "sub-unmapped")
    create(
      :billing_engine_migration,
      organization:,
      shadow_organization:,
      plan_mapping: {"legacy" => "catalog"},
      events_copy_source: "raw_topic"
    )
  end

  it "copies the event to the shadow organization and waits for Kafka to acknowledge it" do
    freeze_time do
      expect(result).to be_success
      expect(result.copied_count).to eq(1)

      expect(karafka_producer).to have_received(:produce_many_sync).once
      expect(kafka_messages.map { it[:topic] }).to eq([product_topic])
      expect(copied_payloads).to eq(
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

  context "with events of several subscriptions and organizations" do
    let(:raw_payloads) do
      [
        raw_event(transaction_id: "tr-1"),
        raw_event(transaction_id: "tr-2", external_subscription_id: "sub-unmapped"),
        raw_event(transaction_id: "tr-3", external_subscription_id: nil),
        raw_event(transaction_id: "tr-4", organization_id: other_organization.id, external_subscription_id: "sub-mapped"),
        raw_event(transaction_id: "tr-5", organization_id: other_organization.id, properties: {"ref" => organization.id}),
        raw_event(transaction_id: "tr-6")
      ]
    end

    it "copies the events of mapped subscriptions of the migrated organization in one produce" do
      expect(result.copied_count).to eq(2)
      expect(result.unmapped_count).to eq(2)
      expect(result.invalid_count).to eq(0)
      expect(result.replayed_count).to eq(0)

      expect(karafka_producer).to have_received(:produce_many_sync).once
      expect(copied_payloads.map { it["transaction_id"] }).to eq(%w[tr-1 tr-6])
    end
  end

  context "with several migrations copying from the raw topic" do
    let(:second_organization) { create(:organization) }
    let(:second_shadow_organization) { create(:shadow_organization, clickhouse_events_store: true) }
    let(:raw_payloads) do
      [
        raw_event(transaction_id: "tr-1"),
        raw_event(transaction_id: "tr-2", organization_id: second_organization.id, external_subscription_id: "sub-second")
      ]
    end

    before do
      second_customer = create(:customer, organization: second_organization)
      create(:subscription, customer: second_customer, plan: create(:plan, organization: second_organization, code: "legacy"), external_id: "sub-second")
      create(
        :billing_engine_migration,
        organization: second_organization,
        shadow_organization: second_shadow_organization,
        plan_mapping: {"legacy" => "catalog"},
        events_copy_source: "raw_topic"
      )
    end

    it "produces the copies of each shadow organization in its own call" do
      expect(result.copied_count).to eq(2)

      expect(karafka_producer).to have_received(:produce_many_sync).twice
      expect(copied_payloads.map { it.values_at("organization_id", "transaction_id") })
        .to match_array([[shadow_organization.id, "tr-1"], [second_shadow_organization.id, "tr-2"]])
    end

    context "when Kafka refuses the copies of the second shadow organization" do
      before do
        produce_calls = 0

        allow(karafka_producer).to receive(:produce_many_sync) do |messages|
          produce_calls += 1
          raise WaterDrop::Errors::ProduceManyError.new([], "boom") if produce_calls == 2

          kafka_messages.concat(messages)
        end
      end

      it "raises after the first copies, so the retried batch sends them again" do
        expect { result }.to raise_error(WaterDrop::Errors::ProduceManyError)

        expect(karafka_producer).to have_received(:produce_many_sync).twice
        expect(kafka_messages.size).to eq(1)
      end
    end
  end

  context "with re-enrichment replays" do
    let(:raw_payloads) do
      [
        raw_event(transaction_id: "tr-1", source_metadata: {api_post_processed: true, reprocess: true}),
        raw_event(transaction_id: "tr-2", source_metadata: {api_post_processed: true, reprocess: false}),
        raw_event(transaction_id: "tr-3", source_metadata: "reprocess")
      ]
    end

    it "skips the replays and copies the other events" do
      expect(result.replayed_count).to eq(1)
      expect(result.copied_count).to eq(2)
      expect(copied_payloads.map { it["transaction_id"] }).to eq(%w[tr-2 tr-3])
    end
  end

  context "when no event belongs to a migrated organization" do
    let(:raw_payloads) { [raw_event(organization_id: other_organization.id), nil, "not json"] }

    it "copies nothing" do
      expect(result).to be_success
      expect(result.copied_count).to eq(0)
      expect(result.invalid_count).to eq(0)
      expect(karafka_producer).not_to have_received(:produce_many_sync)
    end
  end

  context "when payloads of the migrated organization are invalid" do
    let(:raw_payloads) do
      [
        "{\"organization_id\":\"#{organization.id}\",",
        [organization.id].to_json,
        raw_event(transaction_id: "tr-1", timestamp: "yesterday"),
        raw_event(transaction_id: "tr-2", timestamp: nil),
        raw_event(transaction_id: "tr-3", code: nil),
        raw_event(transaction_id: nil),
        raw_event(transaction_id: "tr-4")
      ]
    end

    it "skips them and copies the others" do
      expect(result.invalid_count).to eq(6)
      expect(result.copied_count).to eq(1)
      expect(copied_payloads.map { it["transaction_id"] }).to eq(%w[tr-4])
    end
  end

  context "with the timestamp formats the events processor accepts" do
    let(:raw_payloads) do
      [
        raw_event(transaction_id: "tr-1", timestamp: 1_763_900_000),
        raw_event(transaction_id: "tr-2", timestamp: 1_763_900_000.5),
        raw_event(transaction_id: "tr-3", timestamp: "1763900000"),
        raw_event(transaction_id: "tr-4", timestamp: "2025-11-23T12:13:20Z")
      ]
    end

    it "keeps the instant of each" do
      result

      expect(copied_payloads.map { it["timestamp"] }).to eq(%w[1763900000.0 1763900000.5 1763900000.0 1763900000.0])
    end
  end

  context "without an amount or properties" do
    let(:raw_payloads) { [raw_event(precise_total_amount_cents: nil, properties: nil)] }

    it "copies the defaults the API path sends" do
      result

      expect(copied_payloads.first).to include("precise_total_amount_cents" => "0.0", "properties" => {})
    end
  end

  context "without a migration to copy" do
    let(:migrations) { [] }

    it { expect { result }.not_to change(kafka_messages, :size) }
  end

  context "without the product events topic" do
    let(:product_topic) { nil }

    it "fails instead of dropping the copies" do
      expect(result).to be_failure
      expect(result.error.code).to eq("product_raw_events_topic_missing")
      expect(karafka_producer).not_to have_received(:produce_many_sync)
    end
  end

  context "when Kafka refuses the copies" do
    before { allow(karafka_producer).to receive(:produce_many_sync).and_raise(WaterDrop::Errors::ProduceManyError.new([], "boom")) }

    it "raises so the batch is not acknowledged" do
      expect { result }.to raise_error(WaterDrop::Errors::ProduceManyError)
    end
  end
end
