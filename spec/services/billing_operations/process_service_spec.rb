# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ProcessService do
  subject(:result) { described_class.call(customer:, timestamp:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 1, 1), consolidate_invoice:) }
  let(:consolidate_invoice) { false }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "USD", proration: true) }
  let(:rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 1), rate_properties: {"amount" => "31"})
  end
  let(:cursor) { Time.utc(2026, 2, 1) }
  let(:timestamp) { cursor }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 1, next_billing_at: cursor,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
  end

  before do
    rate
    contract_rate_card
  end

  it "atomically records billed coverage and advances the cursor without future operations" do
    expect(BillingOperation.count).to eq(0)
    invoice = result.invoices.sole
    expect(result).to be_success
    expect(invoice).to be_finalized
    expect(invoice.total_amount_cents).to eq(3100)
    expect(invoice.billing_operations.sole).to have_attributes(
      action_type: "close_fixed_arrears", target_cycle_started_at: Time.utc(2026, 1, 1),
      billing_at: cursor, processed_at: timestamp, customer_id: customer.id
    )
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    expect(contract_rate_card.billing_operations.pending).to be_empty
    expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
    expect(contract_rate_card.fees.count).to eq(1)
  end

  context "when the cursor is not due yet" do
    let(:timestamp) { cursor - 1.second }

    it "does not create history or move the cursor" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
    end
  end

  context "with overdue work" do
    let(:timestamp) { Time.utc(2026, 4, 1) }

    it "processes one cursor snapshot per call without skipping intervening cycles" do
      expect(result.invoices.sole.total_amount_cents).to eq(3100)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(described_class.call!(customer:, timestamp:).invoices.sole.total_amount_cents).to eq(3100)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 4, 1))
      expect(contract_rate_card.billing_operations.order(:billing_at).pluck(:target_cycle_started_at))
        .to eq([Time.utc(2026, 1, 1), Time.utc(2026, 2, 1)])
    end
  end

  context "when another customer is due" do
    let(:other_customer) { create(:customer, organization:) }
    let(:other_contract) { create(:contract, organization:, customer: other_customer) }
    let(:other_card) { create(:contract_rate_card, organization:, contract: other_contract, rate_card:, next_billing_at: cursor) }

    before { other_card }

    it "only processes the requested customer" do
      result
      expect(other_card.reload.next_billing_at).to eq(cursor)
      expect(other_card.billing_operations).to be_empty
    end
  end

  context "with a due reconciliation" do
    let(:reconciliation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "reconcile_advance_coverage", causation_type: "rate_change",
        billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    before { reconciliation }

    it "bills the periodic cursor while leaving reconciliation pending" do
      expect(result.invoices.sole.total_amount_cents).to eq(3100)
      expect(reconciliation.reload).to have_attributes(processed_at: nil, invoice_id: nil)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "when only a reconciliation is due" do
    let(:cursor) { Time.utc(2026, 3, 1) }
    let(:reconciliation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "reconcile_advance_coverage", causation_type: "rate_change",
        billing_at: Time.utc(2026, 2, 1), target_cycle_started_at: Time.utc(2026, 1, 1))
    end

    before { reconciliation }

    it "creates no invoice or history and keeps the periodic cursor" do
      expect(described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1)).invoices).to be_empty
      expect(reconciliation.reload.processed_at).to be_nil
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(contract_rate_card.billing_operations).to eq([reconciliation])
    end
  end

  context "when the card is discarded" do
    before { contract_rate_card.discard! }

    it "does not bill its cursor" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations).to be_empty
    end
  end

  context "when the cursor changes after the snapshot" do
    before do
      allow(described_class).to receive(:new).and_wrap_original do |original, **kwargs|
        service = original.call(**kwargs)
        allow(service).to receive(:due_operations).and_wrap_original do |load|
          load.call.tap { contract_rate_card.update!(next_billing_at: cursor + 1.day) }
        end
        service
      end
    end

    it "rechecks the cursor under the row lock" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor + 1.day)
    end
  end

  context "when fee computation fails" do
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_bill") }

    before do
      allow(BillingOperations::ComputeInvoiceService).to receive(:call!).and_raise(BaseService::FailedResult.new(failure, "cannot bill"))
    end

    it "leaves the cursor for retry without output or history" do
      expect(result).to be_failure
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(contract_rate_card.billing_operations).to be_empty
      expect(Invoice.where(customer:)).to be_empty
      expect(contract_rate_card.fees).to be_empty
    end
  end

  context "when advancing the cursor fails" do
    before { allow(ContractRateCards::AdvanceBillingClockService).to receive(:call!).and_raise("cursor failed") }

    it "rolls back billing output and completed history" do
      expect { result }.to raise_error("cursor failed")
      expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
      expect(contract_rate_card.billing_operations).to be_empty
      expect(Invoice.where(customer:)).to be_empty
      expect(contract_rate_card.fees).to be_empty
    end
  end

  context "when billing produces no fees" do
    before do
      allow(BillingOperations::ComputeInvoiceService).to receive(:call!) do |billing_segments:, **|
        double(outputs: billing_segments.index_with { [] })
      end
    end

    it "records completion and advances without an empty invoice" do
      expect(result.invoices).to be_empty
      expect(Invoice.where(customer:)).to be_empty
      expect(contract_rate_card.billing_operations.sole).to have_attributes(processed_at: timestamp, invoice_id: nil)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  it "finalizes only after the billing transaction commits", transaction: false do
    depth = ActiveRecord::Base.connection.open_transactions
    allow(Invoices::FinalizeContractInvoiceService).to receive(:call!) do |invoice:|
      expect(ActiveRecord::Base.connection.open_transactions).to eq(depth)
      expect(invoice.billing_operations.sole.processed_at).to eq(timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
    expect(result.invoices.sole).to be_generating
    expect(Invoices::FinalizeContractInvoiceService).to have_received(:call!).once
  end

  context "when finalization fails after billing commits" do
    before { allow(Invoices::FinalizeContractInvoiceService).to receive(:call!).and_raise("finalization failed") }

    it "leaves the generating invoice untouched on retry without repeating billing" do
      expect { result }.to raise_error("finalization failed")
      expect(contract_rate_card.billing_operations.sole.processed_at).to eq(timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      allow(Invoices::FinalizeContractInvoiceService).to receive(:call!).and_call_original
      expect { described_class.call!(customer:, timestamp:) }.not_to change(Fee, :count)
      expect(Invoice.where(customer:).sole).to be_generating
    end
  end

  context "with two cards on separate contracts" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at, consolidate_invoice:) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:, units: 1,
        next_billing_at: cursor, effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
    end

    before { other_card }

    it "keeps non-consolidated invoices separate without persisted operation ids" do
      expect(result.invoices.map(&:total_amount_cents)).to eq([3100, 3100])
    end

    context "with consolidation" do
      let(:consolidate_invoice) { true }

      it "records each card's completed operation on the shared invoice" do
        invoice = result.invoices.sole
        expect(invoice.total_amount_cents).to eq(6200) # Two $31 cards.
        expect(invoice.billing_operations.pluck(:contract_rate_card_id)).to match_array([contract_rate_card.id, other_card.id])
        expect(other_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      end
    end
  end

  context "with two known prices in one cycle" do
    let(:cursor) { Time.utc(2026, 1, 15) }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15), rate_properties: {"amount" => "62"})
    end

    it "bills each arrears slice exactly once" do
      expect(result.invoices.sole.total_amount_cents).to eq(1400) # $31 * 14 / 31 days.
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
      expect(described_class.call!(customer:, timestamp: Time.utc(2026, 2, 1)).invoices.sole.total_amount_cents).to eq(3400) # $62 * 17 / 31 days.
      expect(contract_rate_card.billing_operations.order(:billing_at).pluck(:target_cycle_started_at)).to eq([Time.utc(2026, 1, 1)] * 2)
    end

    context "with advance billing" do
      let(:billing_timing) { "advance" }
      let(:cursor) { Time.utc(2026, 1, 1) }

      it "advances through both purchased slices before the next cycle" do
        expect(result.invoices.sole.total_amount_cents).to eq(1400) # $31 * 14 / 31 days.
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 1, 15))
        expect(described_class.call!(customer:, timestamp: Time.utc(2026, 1, 15)).invoices.sole.total_amount_cents).to eq(3400) # $62 * 17 / 31 days.
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
      end
    end
  end

  context "with metered arrears" do
    let(:metric) { create(:billable_metric, organization:, aggregation_type: :count_agg) }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) { create(:rate_card, organization:, product:, currency: "USD") }

    before do
      create(:event, organization:, customer:, external_subscription_id: contract.external_id,
        code: metric.code, timestamp: Time.utc(2026, 1, 10), properties: {})
    end

    it "records usage billing and advances its cursor" do
      expect(result.invoices.sole.fees.sole).to have_attributes(units: 1, amount_cents: 3100)
      expect(contract_rate_card.billing_operations.sole.action_type).to eq("close_metered_arrears")
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
    end
  end

  context "with recurring metered advance" do
    let(:cursor) { Time.utc(2026, 1, 1) }
    let(:metric) { create(:sum_billable_metric, organization:, recurring: true, field_name: "quantity") }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD", display_on_invoice: true) }

    it "records a no-output renewal and advances" do
      expect(result.invoices).to be_empty
      expect(contract_rate_card.billing_operations.sole).to have_attributes(action_type: "renew_recurring_metered_advance", processed_at: timestamp)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    end
  end

  context "with paid advance fees to regroup" do
    let(:metric) { create(:billable_metric, organization:) }
    let(:product) { create(:product, :metered, organization:, billable_metric: metric) }
    let(:rate_card) do
      create(:rate_card, :advance, organization:, product:, currency: "USD", display_on_invoice: false, regroup_paid_fees: :invoice)
    end
    let(:source_operation) do
      build(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "regroup_paid_fees",
        billing_at: cursor, target_cycle_started_at: Time.utc(2026, 1, 1))
    end
    let(:paid_fee) do
      segment = BillingOperations::ResolveSegmentsService.call!(operation: source_operation).segments.sole
      metered_item = Fees::ChargeService::MeteredItem.from_billing_segment(billing_segment: segment)
      create(:fee, :succeeded, invoice: nil, subscription: nil, organization:, billing_entity: customer.billing_entity,
        contract:, contract_rate_card:, rate_card_rate: rate, invoiceable: product, fee_type: :product,
        amount_currency: "USD", amount_cents: 500, pay_in_advance: true, succeeded_at: Time.utc(2026, 1, 10),
        properties: metered_item.filtered_for_charge_boundaries)
    end

    before { paid_fee }

    it "attaches the paid fee without charging again" do
      expect(result.invoices.sole.fees).to eq([paid_fee])
      expect(contract_rate_card.billing_operations.sole.invoice_id).to eq(paid_fee.reload.invoice_id)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 3, 1))
      expect(described_class.call!(customer:, timestamp:).invoices).to be_empty
    end
  end
end
