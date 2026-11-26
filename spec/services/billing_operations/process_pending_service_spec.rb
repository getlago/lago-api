# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ProcessPendingService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "advance" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: true) }
  let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_properties: {"amount" => "31"}) }
  let(:timestamp) { Time.utc(2026, 1, 20) }
  let(:cursor) { Time.utc(2026, 1, 1) }
  let(:card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 8, next_billing_at: cursor,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
  end
  let(:periodic) do
    create(:billing_operation, organization:, customer:, contract_rate_card: card, action_type: card.periodic_billing_action,
      billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
  end
  let(:change_time) { Time.utc(2026, 1, 15, 0, 0, 0, 123456) }
  let(:change) do
    create(:billing_operation, organization:, customer:, contract_rate_card: card, action_type: "reconcile_advance_coverage",
      reason: :contract_units_change, billing_at: change_time, target_cycle_started_at: Time.utc(2026, 1, 1),
      units_before: 8, units_after: 10)
  end

  before do
    rate
    periodic
    change
  end

  it "bills renewal before its adjustment, retaining the original change time" do
    expect(result).to be_success
    expect(result.invoices.map(&:total_amount_cents)).to eq([24_800, 3400]) # 8 × 3100, then 2 × 3100 × 17/31 (rounded).
    expect(change.reload).to have_attributes(billing_at: change_time, processed_at: timestamp)
    expect(change.segments.sole.started_at).to eq(change_time)
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
  end

  context "with arrears billing" do
    let(:billing_timing) { "arrears" }
    let(:cursor) { Time.utc(2026, 2, 1) }
    let(:timestamp) { cursor }
    let(:change_time) { Time.utc(2026, 1, 15) }

    it "completes reconciliation without an invoice and bills the quantity history periodically" do
      expect(result.invoices.sole.total_amount_cents).to eq(24_800 + 3400) # 8 units all month plus 2 units for 17 days.
      expect(change.reload).to have_attributes(processed_at: timestamp, invoice_id: nil)
      expect(change.segments).to be_empty
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "with multiple units changes" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card: card, action_type: "reconcile_advance_coverage",
        reason: :contract_units_change, billing_at: Time.utc(2026, 1, 16), target_cycle_started_at: Time.utc(2026, 1, 1),
        units_before: 10, units_after: 8)
    end

    it "loads history once across both processors and all reconciliation batches" do
      queries = capture_sql { result }
      history_queries = queries.grep(/SELECT "billing_operations"\."contract_rate_card_id", "billing_operations"\."billing_at", "billing_operations"\."units_after"/)

      expect(history_queries.size).to eq(1)
      expect(result.invoices.map(&:total_amount_cents)).to eq([24_800, 3400]) # The decrease does not refund coverage bought on 15 January.
      expect(card.units_changes.pending).to be_empty
    end
  end

  context "with overdue periodic operations" do
    let(:timestamp) { Time.utc(2026, 4, 1) }
    let(:later_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card: card, action_type: card.periodic_billing_action,
        billing_at: Time.utc(2026, 2, 1), target_cycle_started_at: Time.utc(2026, 2, 1))
    end

    before { later_operation }

    it "processes only one periodic operation for the card while completing earlier reconciliation" do
      expect(result.invoices.map(&:total_amount_cents)).to eq([24_800, 3400]) # January renewal plus the additional coverage from 15 January.
      expect(periodic.reload.processed_at).to eq(timestamp)
      expect(change.reload.processed_at).to eq(timestamp)
      expect(later_operation.reload.processed_at).to be_nil
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end
end
