# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyRateChangeService do
  subject(:result) { described_class.call(customer:, rate_card_rate_id: new_rate.id) }

  let(:organization) { create(:organization, feature_flags: []) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:billing_scope) { "segment" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: true, currency: "USD") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, billing_scope:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1), units: 1)
  end
  let(:old_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1), rate_properties: {"amount" => "30"})
  end
  let(:effective_from) { Time.utc(2026, 11, 15) }
  # Set only by the reconciliation contexts, whose path still reads the clock.
  let(:initial_cursor) { nil }
  let(:new_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from:, rate_properties: {"amount" => "60"})
  end
  let(:initialize_clock) do
    ContractRateCards::ResetBillingClockService.call!(contract_rate_card:)
    contract_rate_card.update!(next_billing_at: initial_cursor) if initial_cursor
  end

  around do |example|
    travel_to(example.metadata.fetch(:billing_time, Time.utc(2026, 11, 12))) { example.run }
  end

  before do
    old_rate
    initialize_clock
    new_rate
  end

  def bill(timestamp)
    BillingOperations::ScheduleService.call!(customer:, timestamp:)
    BillingOperations::ProcessService.call!(customer:, timestamp:).invoices
  end

  it "moves the clock to the close at the rate change and bills each slice at its price" do
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))

    expect(result).to be_success
    expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    expect(BillingOperation.count).to eq(0)
    expect(BillingOperations::ProcessJob).not_to have_been_enqueued

    expect(bill(effective_from).sole.total_amount_cents).to eq(1400) # $30 * 14/30 days before the change.
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    expect(bill(Time.utc(2026, 12, 1)).sole.total_amount_cents).to eq(3200) # $60 * 16/30 days after it.
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
  end

  it "keeps the same clock on repeated delivery" do
    result
    expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.not_to change(BillingOperation, :count)
    expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
  end

  context "when the scope covers the cycle" do
    let(:billing_scope) { "cycle" }

    it "keeps the cycle close and bills both prices on the same invoice" do
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(bill(effective_from)).to be_empty

      invoice = bill(Time.utc(2026, 12, 1)).sole
      expect(invoice.total_amount_cents).to eq(1400 + 3200) # $30 * 14/30 days, then $60 * 16/30 days.
      expect(invoice.fees.order(:amount_cents).pluck(:rate_card_rate_id, :amount_cents)).to eq([
        [old_rate.id, 1400], [new_rate.id, 3200]
      ])
      expect(invoice.billing_operations.sole).to have_attributes(
        target_cycle_started_at: Time.utc(2026, 11, 1), billing_at: Time.utc(2026, 12, 1)
      )
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
      expect(bill(Time.utc(2026, 12, 1))).to be_empty
      expect(contract_rate_card.fees.count).to eq(2)
    end

    context "when a historical rate is inserted after the cycle was closed", billing_time: Time.utc(2026, 12, 5) do
      let(:closed_invoice) do
        travel_to(Time.utc(2026, 12, 1))
        invoice = bill(Time.current).sole
        travel_to(Time.utc(2026, 12, 5))
        invoice
      end
      # Legacy/imported rows can bypass the API's rejection of backdated rates.
      let(:new_rate) do
        closed_invoice
        super()
      end

      it "keeps the completed invoice and operation unchanged and continues with the next cycle" do
        invoice_attributes = closed_invoice.attributes
        fee_attributes = closed_invoice.fees.order(:id).map(&:attributes)
        completed_operation = closed_invoice.billing_operations.sole
        operation_attributes = completed_operation.attributes
        expect(closed_invoice.total_amount_cents).to eq(3000) # $30 for the full November cycle before the historical rate existed.

        expect { result }.not_to change(BillingOperation, :count)
        expect(result).to be_success
        expect(closed_invoice.reload.attributes).to eq(invoice_attributes)
        expect(closed_invoice.fees.order(:id).map(&:attributes)).to eq(fee_attributes)
        expect(completed_operation.reload.attributes).to eq(operation_attributes)
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
        expect(bill(Time.current)).to be_empty
        expect(customer.invoices.pluck(:id)).to eq([closed_invoice.id])
      end
    end
  end

  context "when the rate starts on the boundary of the close still owed" do
    let(:effective_from) { Time.utc(2026, 12, 1) }

    it "keeps November due on its boundary, at the old price" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(bill(Time.utc(2026, 12, 1)).sole.total_amount_cents).to eq(3000) # $30 for the whole of November.
    end
  end

  context "when an earlier close is still owed" do
    let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 10, 1)) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: Date.new(2026, 10, 1), billing_anchor_date: Date.new(2026, 10, 1), units: 1)
    end
    let(:old_rate) do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 10, 1), rate_properties: {"amount" => "30"})
    end

    it "keeps the clock on the owed close" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 1))
    end
  end

  context "when November was already billed" do
    let(:effective_from) { Time.utc(2026, 12, 15) }

    before { bill(Time.utc(2026, 12, 1)) }

    it "plans from the last billing without reopening it" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the card has no clock" do
    before { contract_rate_card.update!(next_billing_at: nil) }

    it "gives it one from its billing history" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when planning fails for another card" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: Time.utc(2026, 12, 1))
    end
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      other_card
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_wrap_original do |original, **attributes|
        raise BaseService::FailedResult.new(failure, "cannot schedule") if attributes[:contract_rate_card] == other_card

        original.call(**attributes)
      end
    end

    it "returns the failure and rolls back the clocks already moved" do
      expect(result).to be_failure
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(other_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "when reconciliation creation fails on the second card", transaction: false do
    let(:billing_timing) { "advance" }
    let(:initial_cursor) { effective_from }
    let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:operation_counts_during_creation) { [] }
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_create") }

    before do
      other_card
      allow(BillingOperations::CreateService).to receive(:call!).and_wrap_original do |original, **attributes|
        if operation_counts_during_creation.empty?
          original.call(**attributes).tap do
            operation_counts_during_creation << BillingOperation.count
          end
        else
          operation_counts_during_creation << BillingOperation.count
          raise BaseService::FailedResult.new(failure, "cannot create")
        end
      end
    end

    it "rolls back the first created operation and skips processing enqueue" do
      expect(result).to be_failure
      expect(operation_counts_during_creation).to eq([1, 1])
      expect(BillingOperation.where(contract_rate_card_id: [contract_rate_card.id, other_card.id])).to be_empty
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "when filtering cards by contract status and start time" do
    let(:future_contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 13))
    end
    let(:future_card) do
      create(:contract_rate_card, organization:, contract: future_contract, rate_card:,
        effective_date: Date.new(2026, 11, 13), billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:canceled_contract) do
      create(:contract, :canceled, organization:, customer:, started_at: contract.started_at)
    end
    let(:canceled_card) do
      create(:contract_rate_card, organization:, contract: canceled_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:planned_card_ids) { [] }

    before do
      future_card
      canceled_card
      allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_wrap_original do |original, **attributes|
        planned_card_ids << attributes[:contract_rate_card].id
        original.call(**attributes)
      end
    end

    it "includes only active contracts that have started" do
      result

      expect(planned_card_ids).to eq([contract_rate_card.id])
    end
  end

  context "when filtering cards by their contract end" do
    let(:before_end_contract) do
      create(:contract, organization:, customer:, started_at: contract.started_at, ended_at: Time.utc(2026, 11, 15))
    end
    let(:equal_end_contract) do
      create(:contract, organization:, customer:, started_at: contract.started_at, ended_at: Time.utc(2026, 11, 15))
    end
    let(:after_end_contract) do
      create(:contract, organization:, customer:, started_at: contract.started_at, ended_at: Time.utc(2026, 11, 15))
    end
    let(:before_end_card) do
      create(:contract_rate_card, organization:, contract: before_end_contract, rate_card:,
        effective_date: Date.new(2026, 11, 14), billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:equal_end_card) do
      create(:contract_rate_card, organization:, contract: equal_end_contract, rate_card:,
        effective_date: Date.new(2026, 11, 15), billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:after_end_card) do
      create(:contract_rate_card, organization:, contract: after_end_contract, rate_card:,
        effective_date: Date.new(2026, 11, 16), billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:planned_card_ids) { [] }

    before do
      before_end_card
      equal_end_card
      after_end_card
      allow(Billing::RateCards::BuildScheduleService).to receive(:call!).and_wrap_original do |original, **attributes|
        planned_card_ids << attributes[:contract_rate_card].id
        original.call(**attributes)
      end
    end

    it "includes cards starting before the contract end, but excludes equal or later dates" do
      result

      expect(planned_card_ids).to match_array([contract_rate_card.id, before_end_card.id])
    end
  end

  context "when a fixed-advance schedule has no planned operation" do
    let(:billing_timing) { "advance" }
    let(:initial_cursor) { effective_from }
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1), ended_at: Time.utc(2026, 11, 15))
    end

    it "succeeds without creating a reconciliation or enqueueing processing" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(result).to be_success
      expect(result.billing_operations).to be_empty
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end

    context "when the rate starts after the contract end" do
      let(:effective_from) { Time.utc(2026, 11, 20) }

      it "succeeds without creating a reconciliation or enqueueing processing" do
        expect { result }.not_to change(BillingOperation, :count)
        expect(result).to be_success
        expect(result.billing_operations).to be_empty
        expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      end
    end
  end

  context "when an arrears card still owes its final close and the rate starts after the contract end" do
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1), ended_at: Time.utc(2026, 11, 15))
    end
    let(:effective_from) { Time.utc(2026, 11, 20) }

    it "keeps the final close on the clock" do
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 15))
    end
  end

  context "when termination wins the customer lock" do
    before do
      allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **kwargs, &block|
        contract.update!(status: :terminated, terminated_at: Time.current)
        original.call(**kwargs, &block)
      end
    end

    it "leaves the clock to termination planning" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "when the rate was deleted after its creation was applied" do
    before do
      described_class.call!(customer:, rate_card_rate_id: new_rate.id)
      new_rate.discard!
    end

    it "replans from the remaining rates" do
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  context "when the product is metered" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: false) }

    it "moves the metered close to the rate change" do
      expect(contract_rate_card.periodic_billing_action).to eq("close_metered_arrears")
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the card has no periodic action" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance", display_on_invoice: true) }

    it "clears the billing date, as no obligation falls due" do
      expect(contract_rate_card.periodic_billing_action).to be_nil
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(BillingOperation.count).to eq(0)
    end
  end

  context "with purchased advance coverage" do
    let(:billing_timing) { "advance" }
    let(:planned_operations) { [] }
    let(:advance_activation_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "renew_fixed_advance", reason: "contract_activation",
        billing_at: contract.started_at, target_cycle_started_at: contract.started_at)
    end
    let(:initialize_clock) do
      advance_activation_operation
      BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 11, 1))
      contract_rate_card.update!(next_billing_at: effective_from)
    end

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        original.call(**attributes).tap do |plan_result|
          planned_operations << plan_result.planned_operation
        end
      end
    end

    it "persists a reconciliation using the planned dates and enqueues only its creation" do
      reconciliation = result.billing_operations.sole
      expect(reconciliation).to have_attributes(action_type: "reconcile_advance_coverage", billing_at: effective_from, processed_at: nil)
      expect(planned_operations.sole).to have_attributes(
        cycle_started_at: Time.utc(2026, 11, 1), billing_at: effective_from
      )
      expect(reconciliation).to have_attributes(
        billing_at: planned_operations.sole.billing_at,
        target_cycle_started_at: planned_operations.sole.cycle_started_at,
        coverage_started_at: effective_from, coverage_ended_at: Time.utc(2026, 12, 1)
      )
      expect(reconciliation.reload.segments.sole).to have_attributes(rate_card_rate: new_rate, started_at: effective_from, ended_at: Time.utc(2026, 12, 1))
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id).once
      expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.to change(BillingOperation, :count).by(1)
      expect(reconciliation.reload.processed_at).to be_nil
      expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id).twice
    end
  end
end
