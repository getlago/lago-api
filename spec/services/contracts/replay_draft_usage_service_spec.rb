# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::ReplayDraftUsageService do
  subject(:result) { described_class.call(contract:, published_at:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:billable_metric, organization:, code: "draft-usage", aggregation_type: "count_agg") }
  let(:product) { create(:product, organization:, billable_metric:) }
  let(:billing_timing) { "advance" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:) }
  let(:started_at) { Time.zone.parse("2026-11-01 00:00:00") }
  let(:published_at) { Time.zone.parse("2026-11-20 10:00:00") }
  let(:contract) { create(:contract, organization:, customer:, started_at:) }
  let(:replayed) { [] }

  around { |example| travel_to(Time.zone.parse("2026-11-20 10:00:20")) { example.run } }

  before do
    create(:contract_rate_card, organization:, contract:, rate_card:)
    allow(Events::PayInAdvanceService).to receive(:call!) { |event:| replayed << event.transaction_id }
  end

  context "with the PostgreSQL event store" do
    before do
      {
        "before_start" => "2026-10-31 23:59:59",
        "future" => "2026-11-22 08:00:00",
        "at_start" => "2026-11-01 00:00:00",
        "later_during_draft" => "2026-11-19 10:00:00",
        "during_draft" => "2026-11-05 10:00:00",
        "while_publishing" => "2026-11-20 10:00:05"
      }.each do |transaction_id, timestamp|
        create(:event, organization_id: organization.id, external_subscription_id: contract.external_id,
          code: billable_metric.code, timestamp: Time.zone.parse(timestamp), transaction_id:)
      end
      create(:event, organization_id: organization.id, external_subscription_id: contract.external_id,
        code: "other-metric", timestamp: Time.zone.parse("2026-11-05 10:00:00"), transaction_id: "other_metric")
    end

    it "bills the advance card's events from the start, in timestamp order, with no upper bound" do
      expect(result).to be_success
      expect(replayed).to eq(%w[at_start during_draft later_during_draft while_publishing future])
    end

    context "when the card bills in arrears" do
      let(:billing_timing) { "arrears" }

      it "replays nothing, as periods aggregate those events by timestamp" do
        expect(result).to be_success
        expect(replayed).to be_empty
      end
    end

    context "when the contract is not active" do
      let(:contract) { create(:contract, :canceled, organization:, customer:, started_at:) }

      it "replays nothing" do
        expect(result).to be_success
        expect(replayed).to be_empty
      end
    end
  end

  context "with the ClickHouse event store", clickhouse: true do
    let(:organization) { create(:organization, feature_flags: ["product_catalog"], clickhouse_events_store: true) }
    let(:events_factory) { :clickhouse_events_enriched }
    let(:scope_column) { :external_subscription_id }

    before do
      {
        "before_start" => "2026-10-31 23:59:59",
        "while_publishing" => "2026-11-20 10:00:05",
        "during_draft" => "2026-11-05 10:00:00"
      }.each do |transaction_id, timestamp|
        create(
          events_factory,
          :organization => organization, scope_column => contract.external_id, :code => billable_metric.code,
          :transaction_id => transaction_id, :timestamp => Time.zone.parse(timestamp)
        )
      end
    end

    it "bills the events received from the start, without an id as the processor sends them" do
      expect(result).to be_success
      expect(replayed).to eq(%w[during_draft while_publishing])
      expect(Events::PayInAdvanceService).to have_received(:call!)
        .with(event: having_attributes(id: nil, external_subscription_id: contract.external_id)).twice
    end

    context "when the organization is on the product events pipeline" do
      let(:events_factory) { :clickhouse_product_events_enriched }
      let(:scope_column) { :external_contract_id }

      around do |example|
        ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = "product_events_raw"
        example.run
      ensure
        ENV["LAGO_KAFKA_PRODUCT_RAW_EVENTS_TOPIC"] = nil
      end

      it "reads the product events, keyed by contract" do
        expect(result).to be_success
        expect(replayed).to eq(%w[during_draft while_publishing])
      end
    end

    context "when events reach ClickHouse through Kafka" do
      let(:rate_card) do
        create(:rate_card, organization:, product:, billing_timing:, proration: false).tap do |card|
          create(:rate_card_rate, organization:, rate_card: card, effective_from: started_at,
            billing_interval_count: 1, billing_interval_unit: "month")
        end
      end

      around do |example|
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = "kafka:9092"
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = "events_raw"
        example.run
      ensure
        ENV["LAGO_KAFKA_BOOTSTRAP_SERVERS"] = nil
        ENV["LAGO_KAFKA_RAW_EVENTS_TOPIC"] = nil
      end

      before do
        allow(Events::PayInAdvanceService).to receive(:call!).and_call_original
        contract.applied_rate_cards.sole.update!(effective_date: started_at.to_date, billing_anchor_date: started_at.to_date)
      end

      it "bills the replayed events, as the pay in advance path keeps an event without an id" do
        expect { result }.to have_enqueued_job(Fees::CreatePayInAdvanceJob).exactly(2).times
          .or have_enqueued_job(Invoices::CreatePayInAdvanceChargeJob).exactly(2).times
      end
    end
  end
end
