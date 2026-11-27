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

  context "when one periodic invoice fails" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1)) }
    let(:other_cursor) { Time.utc(2026, 2, 1) }
    let(:other_anchor) { Date.new(2026, 1, 1) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:, units: 8,
        effective_date: Date.new(2026, 1, 1), billing_anchor_date: other_anchor, next_billing_at: other_cursor)
    end
    let(:other_change_time) { Time.utc(2026, 1, 16) }
    let(:other_cycle) { Time.utc(2026, 1, 1) }
    let(:later_change_time) { Time.utc(2026, 1, 17) }
    let(:later_cycle) { other_cycle }
    let(:other_change) do
      create(:billing_operation, organization:, customer:, contract_rate_card: other_card, action_type: "reconcile_advance_coverage",
        reason: :contract_units_change, billing_at: other_change_time, target_cycle_started_at: other_cycle, units_before: 8, units_after: 10)
    end
    let(:later_change) do
      create(:billing_operation, organization:, customer:, contract_rate_card: other_card, action_type: "reconcile_advance_coverage",
        reason: :contract_units_change, billing_at: later_change_time, target_cycle_started_at: later_cycle, units_before: 10, units_after: 11)
    end
    let(:previous_renewal) do
      create(:billing_operation, organization:, customer:, contract_rate_card: other_card, action_type: "renew_fixed_advance",
        billing_at: Time.utc(2026, 1, 1), target_cycle_started_at: Time.utc(2026, 1, 1), processed_at: Time.utc(2026, 1, 1))
    end
    let(:failed_attempts) { [] }
    let(:billing_failure) do
      BillingOperations::ComputeInvoiceService::Result.new.tap do |failure|
        failure.single_validation_failure!(field: :invoice, error_code: "value_is_invalid")
      end
    end

    before do
      previous_renewal.segments.create!(organization:, rate_card_rate: rate, position: 0,
        started_at: Time.utc(2026, 1, 1), ended_at: other_cursor, proration_ratio: 1, units: 8)
      other_change
      later_change
      allow(BillingOperations::ComputeInvoiceService).to receive(:call!).and_wrap_original do |original, **arguments|
        if arguments.fetch(:billing_segments).any? { it.contract_rate_card.id == card.id }
          failed_attempts << card.id
          billing_failure.raise_if_error!
        end
        original.call(**arguments)
      end
    end

    it "bills independent adjustments, leaves dependent changes pending and returns the original error" do
      expect(result).to be_failure
      expect(result.error).to eq(billing_failure.error)
      expect(result.invoices.map(&:total_amount_cents)).to eq([3200, 1500]) # 2 × 3100 × 16/31, then 1 × 3100 × 15/31.
      expect(other_change.reload.processed_at).to eq(timestamp)
      expect(later_change.reload.processed_at).to eq(timestamp)
      expect(periodic.reload.processed_at).to be_nil
      expect(change.reload.processed_at).to be_nil
      expect(card.reload.next_billing_at).to eq(cursor)
      expect(failed_attempts).to eq([card.id])
    end

    context "when another card needs reconciliation before its renewal" do
      let(:other_cursor) { Time.utc(2026, 1, 10) }
      let(:other_anchor) { Date.new(2026, 1, 10) }
      let(:other_change_time) { Time.utc(2026, 1, 5) }
      let(:later_change_time) { Time.utc(2026, 1, 15) }
      let(:later_cycle) { Time.utc(2026, 1, 10) }
      let(:other_periodic) do
        create(:billing_operation, organization:, customer:, contract_rate_card: other_card, action_type: "renew_fixed_advance",
          billing_at: other_cursor, target_cycle_started_at: other_cursor)
      end

      before { other_periodic }

      it "continues independent work across multiple processing passes" do
        expect(result).to be_failure
        expect(result.error).to eq(billing_failure.error)
        expect(result.invoices.map(&:total_amount_cents)).to eq([1000, 31_000, 2600])
        # 2 × 3100 × 5/31 before renewal; 10 × 3100 at renewal; 1 × 3100 × 26/31 afterward.
        expect(other_change.reload.processed_at).to eq(timestamp)
        expect(other_periodic.reload.processed_at).to eq(timestamp)
        expect(later_change.reload.processed_at).to eq(timestamp)
        expect(periodic.reload.processed_at).to be_nil
        expect(change.reload.processed_at).to be_nil
        expect(failed_attempts).to eq([card.id])
      end
    end
  end

  context "when billed advance coverage has no saved quantities" do
    let(:previous_invoice) { create(:invoice, organization:, customer:, invoice_type: :contract) }

    before do
      periodic.update!(processed_at: cursor, invoice: previous_invoice)
      card.update!(next_billing_at: Time.utc(2026, 2, 1))
    end

    it "leaves the adjustment pending without creating another invoice" do
      expect(result).to be_failure
      expect(customer.invoices.count).to eq(1)
      expect(result.error.messages).to eq(operation: ["missing_saved_units"])
      expect(result.invoices).to be_empty
      expect(change.reload).to have_attributes(processed_at: nil, invoice_id: nil)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end

  context "when reconciliation fails" do
    let(:billing_failure) do
      BillingOperations::ComputeInvoiceService::Result.new.tap do |failure|
        failure.single_validation_failure!(field: :invoice, error_code: "value_is_invalid")
      end
    end

    before do
      allow(BillingOperations::ComputeInvoiceService).to receive(:call!).and_wrap_original do |original, **arguments|
        billing_failure.raise_if_error! if arguments.fetch(:billing_segments).any? { !it.prepaid_units.nil? }
        original.call(**arguments)
      end
    end

    it "preserves the periodic invoice and returns the reconciliation error" do
      expect(result).to be_failure
      expect(result.error).to eq(billing_failure.error)
      expect(result.invoices.sole.total_amount_cents).to eq(24_800) # 8 × 3100 for the full period.
      expect(periodic.reload.processed_at).to eq(timestamp)
      expect(change.reload.processed_at).to be_nil
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end
end
