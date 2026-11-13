# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::CompareContractUsageService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization, feature_flags: [:product_catalog]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.zone.parse("2027-01-01")) }
  let(:billable_metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "value") }
  let(:product) { create(:product, :metered, organization:, billable_metric:) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR") }
  # Created before the snapshot's watermark, so the card is not a change since the snapshot
  let(:card_created_at) { Time.zone.parse("2026-12-01") }
  let(:segment_started_at) { Time.zone.parse("2027-02-01") }
  let(:snapshot_to_datetime) { BillingSegment.inclusive_end(segment_started_at) }
  let(:snapshot_units) { 5 }

  before do
    create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2027, 1, 1),
      billing_anchor_date: Date.new(2027, 1, 1), created_at: card_created_at)
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.zone.parse("2027-01-01"), rate_properties: {"amount" => "1"})

    create_event(timestamp: Time.zone.parse("2027-01-10"), value: 5)
    create_event(timestamp: Time.zone.parse("2027-02-05"), value: 3)
    create(:contract_recurring_aggregation_snapshot, organization:, contract:, product:, units: snapshot_units,
      events_count: 1, to_datetime: snapshot_to_datetime, watermark: segment_started_at)

    travel_to(Time.zone.parse("2027-02-10 12:00:00"))
    stub_const("#{described_class}::RECHECK_DELAY", 0)
  end

  def create_event(timestamp:, value:)
    create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: billable_metric.code,
      timestamp:, created_at: timestamp, properties: {value:})
  end

  it "computes both paths and reports no difference when the snapshot is right" do
    expect(result).to be_success
    expect(result.compared_items_count).to eq(1)
    expect(result.snapshot_items_count).to eq(1)
    expect(result.rechecked).to be(false)
    expect(result.differences).to be_empty
    expect(result.rows.sole).to have_attributes(
      item_id: product.id,
      billable_metric_code: billable_metric.code,
      filter_id: nil,
      grouped_by: {},
      snapshot_read: true,
      snapshot: have_attributes(units: 5 + 3, events_count: 2, amount_cents: 800), # snapshot + February event, at 1 EUR
      full_scan: have_attributes(units: 5 + 3, events_count: 2, amount_cents: 800) # January + February events
    )
  end

  it "persists nothing and leaves the read gate untouched" do
    expect { result }.not_to change { [Fee.count, CachedAggregation.count, ContractRecurringAggregationSnapshot.count] }
    expect(RecurringAggregationSnapshots.read_enabled?(organization)).to be(false)
  end

  context "when the snapshot disagrees with the full history" do
    let(:snapshot_units) { 20 }

    it "reports the leaf after checking it again" do
      expect(result.rechecked).to be(true)
      expect(result.differences.sole).to have_attributes(
        item_id: product.id,
        snapshot: have_attributes(units: 20 + 3), # snapshot + February event
        full_scan: have_attributes(units: 5 + 3)
      )
    end
  end

  context "with a card of a product the snapshots do not serve" do
    let(:other_product) do
      create(:product, :metered, organization:, billable_metric: create(:sum_billable_metric, organization:, field_name: "value"))
    end
    let(:other_rate_card) { create(:rate_card, organization:, product: other_product, currency: "EUR") }

    before do
      create(:contract_rate_card, organization:, contract:, rate_card: other_rate_card, effective_date: Date.new(2027, 1, 1),
        billing_anchor_date: Date.new(2027, 1, 1), created_at: card_created_at)
      create(:rate_card_rate, organization:, rate_card: other_rate_card, effective_from: Time.zone.parse("2027-01-01"),
        rate_properties: {"amount" => "1"})
    end

    it "compares only the recurring product" do
      expect(result.compared_items_count).to eq(1)
      expect(result.rows.map(&:item_id)).to eq([product.id])
    end
  end

  context "with a card scoped to a product filter" do
    let(:region) { create(:billable_metric_filter, organization:, billable_metric:, key: "region", values: %w[eu us]) }
    let(:product_filter) { create(:product_filter, organization:, product:, created_at: card_created_at) }
    let(:rate_card) { create(:rate_card, organization:, product:, product_filter:, currency: "EUR") }

    before do
      create(:product_filter_value, organization:, product_filter:, billable_metric_filter: region, value: "eu",
        created_at: card_created_at, updated_at: card_created_at)
      ContractRecurringAggregationSnapshot.update_all(product_filter_id: product_filter.id) # rubocop:disable Rails/SkipsModelValidations
      create_event(timestamp: Time.zone.parse("2027-02-06"), value: 7, region: "us")
    end

    def create_event(timestamp:, value:, region: "eu")
      create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: billable_metric.code,
        timestamp:, created_at: timestamp, properties: {value:, region:})
    end

    it "compares the filter's bucket" do
      expect(result.differences).to be_empty
      expect(result.rows.sole).to have_attributes(
        item_id: product.id,
        filter_id: product_filter.id,
        snapshot_read: true,
        snapshot: have_attributes(units: 5 + 3), # snapshot + February eu event, the us event in no bucket
        full_scan: have_attributes(units: 5 + 3)
      )
    end
  end

  context "when the contract is terminated" do
    before { contract.update!(status: :terminated, terminated_at: Time.zone.parse("2027-01-31")) }

    it "compares nothing, as no segment is open" do
      expect(result.compared_items_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end

  context "when the usage computation fails" do
    before do
      failure = BaseResult.new.tap { it.service_failure!(code: "usage_failed", message: "boom") }
      allow(Contracts::CurrentUsageService).to receive(:call!).and_raise(BaseService::FailedResult.new(failure, "boom"))
    end

    it "returns the failure" do
      expect(result).to be_failure
      expect(result.error.code).to eq("usage_failed")
    end
  end

  context "when the aggregation would not start from the snapshot" do
    let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:, field_name: "value") }
    let(:snapshot_to_datetime) { BillingSegment.inclusive_end(Time.zone.parse("2027-01-01")) }

    it "does not count it as read from a snapshot nor report its difference" do
      expect(result.snapshot_items_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end

  context "when a card of the product was added since the snapshot" do
    let(:card_created_at) { Time.zone.parse("2027-02-05") }

    it "compares nothing, as the product scans its full history" do
      expect(result.snapshot_items_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end

  context "without a snapshot before the segment" do
    before { ContractRecurringAggregationSnapshot.delete_all }

    it "compares nothing" do
      expect(result.compared_items_count).to eq(1)
      expect(result.snapshot_items_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end

  context "with a non recurring billable metric" do
    let(:billable_metric) { create(:sum_billable_metric, organization:, field_name: "value") }

    it "compares nothing" do
      expect(result.compared_items_count).to eq(0)
      expect(result.rows).to be_empty
    end
  end
end
