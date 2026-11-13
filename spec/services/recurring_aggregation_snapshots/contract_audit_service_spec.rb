# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecurringAggregationSnapshots::ContractAuditService do
  subject(:result) { described_class.call!(contract:) }

  let(:organization) { create(:organization, feature_flags: ["recurring_aggregation_snapshots"]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 2, 1)) }
  let(:metric) { create(:sum_billable_metric, :recurring, organization:, field_name: "quantity") }
  let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
  end
  let(:operation) do
    create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "close_metered_arrears",
      billing_at: Time.utc(2026, 3, 1), target_cycle_started_at: Time.utc(2026, 2, 1))
  end
  let(:snapshot) { ContractRecurringAggregationSnapshot.find_by!(contract:) }
  let(:fee) { Fee.find_by!(contract:) }
  let(:now) { Time.utc(2026, 3, 1, 1) }
  let(:february_end) { BillingSegment.inclusive_end(Time.utc(2026, 3, 1)) }
  let(:late_event_created_at) { Time.utc(2026, 1, 1) }

  def create_usage(quantity, timestamp, created_at: Time.utc(2026, 1, 1))
    create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: metric.code,
      timestamp:, created_at:, properties: {quantity:})
  end

  around { |example| travel_to(now) { example.run } }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_model: "standard", rate_properties: {"amount" => "10"})
    create_usage(3, Time.utc(2026, 1, 20))
    create_usage(2, Time.utc(2026, 2, 10), created_at: late_event_created_at)
    operation

    BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 3, 1))
  end

  it "matches the snapshot of the closed slice with the fee of its close operation" do
    expect(result.rows).to eq([
      described_class::Row.new(
        product_id: product.id,
        product_filter_id: nil,
        grouped_by: {},
        to_datetime: february_end,
        snapshot_units: 5, # 3 in January + 2 in February, recurring
        fee_units: 5,
        snapshot_events_count: 2,
        fee_events_count: 2,
        watermark_gap: false
      )
    ])
    expect(result.differences).to be_empty
    expect(result.watermark_gap_rows).to be_empty
    expect(result.periods_without_invoice).to be_empty
  end

  context "with a filtered rate card priced by group, next to an unfiltered one on the same product" do
    let(:region) { create(:billable_metric_filter, organization:, billable_metric: metric, key: "region", values: %w[eu us]) }
    let(:eu_filter) { create(:product_filter, organization:, product:) }
    let(:eu_rate_card) { create(:rate_card, organization:, product:, product_filter: eu_filter, currency: "USD") }
    let(:eu_contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card: eu_rate_card, effective_date: Date.new(2026, 2, 1), billing_anchor_date: Date.new(2026, 2, 1))
    end
    let(:eu_snapshots) { ContractRecurringAggregationSnapshot.where(contract:, product_filter: eu_filter) }

    before do
      create(:product_filter_value, organization:, product_filter: eu_filter, billable_metric_filter: region, value: "eu")
      create(:rate_card_rate, organization:, rate_card: eu_rate_card, effective_from: Time.utc(2026, 1, 1), rate_model: "standard",
        rate_properties: {"amount" => "10", "pricing_group_keys" => ["workspace"]})
      create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: metric.code,
        timestamp: Time.utc(2026, 2, 12), created_at: Time.utc(2026, 1, 1), properties: {quantity: 4, region: "eu", workspace: "a"})
      create(:event, organization:, customer:, external_subscription_id: contract.external_id, code: metric.code,
        timestamp: Time.utc(2026, 2, 14), created_at: Time.utc(2026, 1, 1), properties: {quantity: 6, region: "eu", workspace: "b"})
      create(:billing_operation, organization:, customer:, contract_rate_card: eu_contract_rate_card, action_type: "close_metered_arrears",
        billing_at: Time.utc(2026, 3, 1), target_cycle_started_at: Time.utc(2026, 2, 1))

      BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 3, 1))
      eu_snapshots.find_by!(grouped_by: {"workspace" => "b"}).update!(units: 5)
    end

    it "matches each group of each card with its own fee" do
      expect(eu_snapshots.pluck(:grouped_by, :units)).to contain_exactly([{"workspace" => "a"}, 4], [{"workspace" => "b"}, 5])
      expect(result.rows.map { [it.product_filter_id, it.grouped_by, it.snapshot_units, it.fee_units] }).to contain_exactly(
        [nil, {}, 5, 5], # the unfiltered card: the events of no filter, 3 + 2
        [eu_filter.id, {"workspace" => "a"}, 4, 4],
        [eu_filter.id, {"workspace" => "b"}, 5, 6] # snapshot edited above
      )
      expect(result.differences.map(&:grouped_by)).to eq([{"workspace" => "b"}])
    end
  end

  context "when the snapshot differs from the fee" do
    before { snapshot.update!(units: 4) }

    it "reports the difference" do
      expect(result.differences.sole).to have_attributes(snapshot_units: 4, fee_units: 5, snapshot_events_count: 2, fee_events_count: 2)
    end
  end

  context "with an event ingested after the snapshot's watermark" do
    # After the watermark, five minutes before the close, and before the fee
    let(:late_event_created_at) { now - 1.minute }

    it "reports the leaf apart, as the late event explains it" do
      expect(result.watermark_gap_rows.sole).to have_attributes(snapshot_units: 3, fee_units: 5, snapshot_events_count: 1, fee_events_count: 2)
      expect(result.differences).to be_empty
    end
  end

  context "when the close billed no fee" do
    before do
      fee.discard!
      operation.update!(invoice: nil)
      snapshot.update!(units: 0, events_count: 0)
    end

    it "compares the snapshot with zero" do
      expect(result.rows.sole).to have_attributes(snapshot_units: 0, fee_units: 0)
      expect(result.differences).to be_empty
      expect(result.periods_without_invoice).to be_empty
    end
  end

  context "with a snapshot of a slice no processed close operation billed" do
    before do
      create(:contract_recurring_aggregation_snapshot, organization:, contract:, product:, to_datetime: BillingSegment.inclusive_end(Time.utc(2026, 4, 1)), units: 9)
    end

    it "reports the period without invoice" do
      expect(result.periods_without_invoice).to eq([
        described_class::Period.new(product_id: product.id, product_filter_id: nil, to_datetime: BillingSegment.inclusive_end(Time.utc(2026, 4, 1)))
      ])
      expect(result.rows.size).to eq(1)
    end
  end

  context "with the snapshots of another contract" do
    before do
      create(:contract_recurring_aggregation_snapshot, organization:, product:, to_datetime: february_end, units: 9)
    end

    it "leaves them out" do
      expect(result.rows.size).to eq(1)
      expect(result.periods_without_invoice).to be_empty
    end
  end
end
