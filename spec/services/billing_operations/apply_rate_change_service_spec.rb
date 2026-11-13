# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ApplyRateChangeService do
  subject(:result) { described_class.call(customer:, rate_card_rate_id: new_rate.id) }

  let(:organization) { create(:organization, feature_flags: []) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 11, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_timing) { "arrears" }
  let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: true, currency: "USD") }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:,
      effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1), units: 1)
  end
  let(:old_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 1), rate_properties: {"amount" => "30"})
  end
  let(:effective_from) { Time.utc(2026, 11, 15) }
  let(:initial_cursor) { effective_from }
  let(:new_rate) do
    create(:rate_card_rate, organization:, rate_card:, effective_from:, rate_properties: {"amount" => "60"})
  end
  let(:november_closing_operation) do
    create(:billing_operation, organization:, customer:, contract_rate_card:,
      action_type: "close_fixed_arrears", causation_type: "contract_activation",
      billing_at: Time.utc(2026, 12, 1), target_cycle_started_at: Time.utc(2026, 11, 1))
  end
  let(:earlier_rates) { [] }
  let(:initialize_clock) do
    ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, timestamp: contract.started_at)
      .tap { contract_rate_card.update!(next_billing_at: initial_cursor) }
  end

  around do |example|
    travel_to(example.metadata.fetch(:billing_time, Time.utc(2026, 11, 12))) { example.run }
  end

  before do
    old_rate
    initialize_clock
    earlier_rates
    new_rate
  end

  context "with a persisted November closing operation" do
    before { november_closing_operation }

    it "resets to the new rate boundary and bills the November cycle" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(result).to be_success
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued

      november_invoice = BillingOperations::ProcessService.call!(customer:, timestamp: effective_from).invoices.sole
      expect(november_invoice.total_amount_cents).to eq(1400) # $30 * 14/30 days through the rate boundary.
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
    end
  end

  it "keeps the same cursor on repeated delivery" do
    result
    expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.not_to change(BillingOperation, :count)
    expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
  end

  context "when resetting the arrears cursor" do
    let(:planned_schedules) { [] }

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        original.call(**attributes).tap do |plan_result|
          planned_schedules << plan_result.schedule unless attributes.key?(:schedule)
        end
      end
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_call_original
    end

    it "passes the schedule from the plan to the reset service" do
      result

      expect(ContractRateCards::ResetBillingClockService).to have_received(:call!).with(
        hash_including(timestamp: effective_from, schedule: be(planned_schedules.sole))
      )
    end
  end

  context "when planning fails for another card" do
    let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      other_card
      calls = 0
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        if !attributes.key?(:schedule) && attributes[:timestamp] == new_rate.effective_from
          calls += 1
          raise BaseService::FailedResult.new(failure, "cannot schedule") if calls == 2
        end

        original.call(**attributes)
      end
    end

    it "returns the failure without enqueueing processing" do
      expect(result).to be_failure
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(other_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperation.count).to eq(0)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "when reconciliation creation fails on the second card", transaction: false do
    let(:billing_timing) { "advance" }
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

  context "with an out-of-order rate job" do
    let(:earlier_rates) do
      [create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 11, 10), rate_properties: {"amount" => "45"})]
    end

    it "ignores a rate older than the current time without moving the cursor" do
      result
      described_class.call!(customer:, rate_card_rate_id: earlier_rates.sole.id)
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "with an earlier unpaid cursor" do
    before { contract_rate_card.update!(next_billing_at: Time.utc(2026, 11, 10)) }

    it "preserves the owed work" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 10))
    end
  end

  context "with a completed November cycle" do
    before do
      november_closing_operation
      contract_rate_card.update!(next_billing_at: Time.utc(2026, 12, 1))
      BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 12, 1))
    end

    it "does not reopen billed coverage" do
      expect { result }.not_to change(BillingOperation, :count)
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
    end
  end

  context "with no cursor" do
    let(:initialize_clock) { contract_rate_card.update!(next_billing_at: nil) }

    it "does not seed an initial chain" do
      result
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(contract_rate_card.billing_operations).to be_empty
    end
  end

  context "when the rate starts at an exact cycle boundary" do
    let(:effective_from) { Time.utc(2026, 12, 1) }

    before { allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_call_original }

    it "uses the reset path at an exact cycle boundary" do
      result
      expect(ContractRateCards::ResetBillingClockService).to have_received(:call!).with(
        hash_including(contract_rate_card:, timestamp: effective_from)
      )
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2027, 1, 1))
    end
  end

  context "with a rate after the cursor but inside the effective window" do
    let(:effective_from) { Time.utc(2026, 12, 15) }
    let(:initial_cursor) { Time.utc(2026, 12, 1) }

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_call_original
    end

    it "resets the cursor to the rate date" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::Schedule::BuildPlannedOperation).to have_received(:call!).with(hash_including(timestamp: effective_from)).at_least(:once)
      expect(ContractRateCards::ResetBillingClockService).to have_received(:call!).with(
        hash_including(contract_rate_card:, timestamp: effective_from)
      )
    end

    it "preserves the earlier unpaid closing boundary" do
      pending "Resetting from the rate date can skip an earlier unpaid closing cycle."

      result
      expect(contract_rate_card.reload.next_billing_at).to eq(initial_cursor)
    end
  end

  context "with a rate before the cursor but after the current time" do
    let(:effective_from) { Time.utc(2026, 11, 20) }
    let(:initial_cursor) { Time.utc(2026, 12, 1) }

    before { allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original }

    it "leaves the outside-window cursor unchanged without enqueueing processing" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(initial_cursor)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
      expect(BillingOperations::Schedule::BuildPlannedOperation).not_to have_received(:call!)
    end
  end

  context "with a rate effective in the future but before the cursor" do
    let(:initial_cursor) { Time.utc(2026, 12, 1) }

    before { allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original }

    it "leaves the outside-window cursor unchanged without enqueueing processing" do
      result

      expect(contract_rate_card.reload.next_billing_at).to eq(initial_cursor)
      expect(BillingOperations::Schedule::BuildPlannedOperation).not_to have_received(:call!)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "when the cursor overlaps the current time through the rate date" do
    let(:interior_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:interior_card) do
      create(:contract_rate_card, organization:, contract: interior_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: Time.utc(2026, 11, 14))
    end
    let(:before_window_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:before_window_card) do
      create(:contract_rate_card, organization:, contract: before_window_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: Time.utc(2026, 11, 10))
    end
    let(:after_window_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:after_window_card) do
      create(:contract_rate_card, organization:, contract: after_window_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: Time.utc(2026, 11, 16))
    end
    let(:planned_card_ids) { [] }

    before do
      interior_card
      before_window_card
      after_window_card
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        planned_card_ids << attributes[:contract_rate_card].id unless attributes.key?(:schedule)
        original.call(**attributes)
      end
    end

    it "plans only cards with a cursor in the inclusive window" do
      result

      expect(planned_card_ids).to match_array([contract_rate_card.id, interior_card.id])
      expect(interior_card.reload.next_billing_at).to eq(effective_from)
      expect(before_window_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 10))
      expect(after_window_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 16))
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
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        planned_card_ids << attributes[:contract_rate_card].id unless attributes.key?(:schedule)
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
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        planned_card_ids << attributes[:contract_rate_card].id unless attributes.key?(:schedule)
        original.call(**attributes)
      end
    end

    it "includes cards starting before the contract end, but excludes equal or later dates" do
      result

      expect(planned_card_ids).to match_array([contract_rate_card.id, before_end_card.id])
    end
  end

  context "when the changed cursor is due and other cards are eligible", billing_time: Time.utc(2026, 11, 15) do
    let(:planned_card_ids) { [] }
    let(:other_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:other_card) do
      create(:contract_rate_card, organization:, contract: other_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: effective_from)
    end
    let(:before_window_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:before_window_card) do
      create(:contract_rate_card, organization:, contract: before_window_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: Time.utc(2026, 11, 14))
    end
    let(:after_window_contract) { create(:contract, organization:, customer:, started_at: contract.started_at) }
    let(:after_window_card) do
      create(:contract_rate_card, organization:, contract: after_window_contract, rate_card:,
        effective_date: contract_rate_card.effective_date, billing_anchor_date: contract_rate_card.billing_anchor_date,
        next_billing_at: Time.utc(2026, 11, 16))
    end

    before do
      other_card
      before_window_card
      after_window_card
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        planned_card_ids << attributes[:contract_rate_card].id unless attributes.key?(:schedule)
        original.call(**attributes)
      end
    end

    it "reschedules endpoint cursors and excludes outside cursors" do
      result

      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(other_card.reload.next_billing_at).to eq(effective_from)
      expect(before_window_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 14))
      expect(after_window_card.reload.next_billing_at).to eq(Time.utc(2026, 11, 16))
      expect(planned_card_ids).to match_array([contract_rate_card.id, other_card.id])
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end

  context "when checking cursor boundaries" do
    before do
      contract_rate_card.update!(next_billing_at: cursor)
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original
    end

    context "with no cursor" do
      let(:cursor) { nil }

      it "does not plan a change" do
        result
        expect(contract_rate_card.reload.next_billing_at).to be_nil
        expect(BillingOperations::Schedule::BuildPlannedOperation).not_to have_received(:call!)
      end
    end

    context "with a cursor equal to the effective date" do
      let(:cursor) { effective_from }

      it "plans and resets the card through the schedule" do
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
        expect(BillingOperations::Schedule::BuildPlannedOperation).to have_received(:call!).with(hash_including(timestamp: effective_from)).at_least(:once)
      end
    end

    context "with a cursor before the effective date" do
      let(:cursor) { Time.utc(2026, 11, 10) }

      it "preserves the overdue cursor without planning" do
        result
        expect(contract_rate_card.reload.next_billing_at).to eq(cursor)
        expect(BillingOperations::Schedule::BuildPlannedOperation).not_to have_received(:call!)
      end
    end
  end

  context "when a fixed-advance schedule has no planned operation" do
    let(:billing_timing) { "advance" }
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

  context "when termination wins the customer lock" do
    before do
      allow(Customers::LockService).to receive(:call!).and_wrap_original do |original, **kwargs, &block|
        contract.update!(status: :terminated, terminated_at: Time.current)
        original.call(**kwargs, &block)
      end
    end

    it "leaves the cursor to termination planning" do
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the rate belongs to another organization" do
    let(:new_rate) { create(:rate_card_rate) }

    it "raises because the scoped rate lookup has no result" do
      expect { result }.to raise_error(NoMethodError)
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the rate was deleted" do
    before { new_rate.discard! }

    it "raises because the discarded rate is not returned by the scoped lookup" do
      expect { result }.to raise_error(NoMethodError)
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
    end
  end

  context "when the product is metered" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, proration: false) }

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_call_original
    end

    it "reschedules metered arrears when its rate changes" do
      expect(contract_rate_card.periodic_billing_action).to eq("close_metered_arrears")
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::Schedule::BuildPlannedOperation).to have_received(:call!).with(hash_including(timestamp: effective_from)).at_least(:once)
      expect(ContractRateCards::ResetBillingClockService).to have_received(:call!).with(
        hash_including(contract_rate_card:, schedule: instance_of(Billing::RateCards::Schedule))
      )
    end
  end

  context "when recurring metered advance is periodic" do
    let(:effective_from) { Time.utc(2026, 12, 15) }
    let(:initial_cursor) { Time.utc(2026, 12, 1) }
    let(:product) do
      create(:product, organization:, billable_metric: create(:sum_billable_metric, :recurring, organization:))
    end
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance", display_on_invoice: true) }

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_call_original
    end

    it "reschedules recurring metered advance through the planned schedule" do
      expect(contract_rate_card.periodic_billing_action).to eq("renew_recurring_metered_advance")
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::Schedule::BuildPlannedOperation).to have_received(:call!).with(hash_including(timestamp: effective_from)).at_least(:once)
      expect(ContractRateCards::ResetBillingClockService).to have_received(:call!).with(
        hash_including(contract_rate_card:, schedule: instance_of(Billing::RateCards::Schedule))
      )
      expect(BillingOperation.count).to eq(0)
    end
  end

  context "when grouping paid advance fees is periodic" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) do
      create(:rate_card, organization:, product:, billing_timing: "advance", regroup_paid_fees: :invoice, display_on_invoice: false)
    end

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_call_original
    end

    it "reschedules grouped advance fees through the planned schedule" do
      expect(contract_rate_card.periodic_billing_action).to eq("regroup_paid_fees")
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::Schedule::BuildPlannedOperation).to have_received(:call!).with(hash_including(timestamp: effective_from)).at_least(:once)
      expect(ContractRateCards::ResetBillingClockService).to have_received(:call!).with(
        hash_including(contract_rate_card:, schedule: instance_of(Billing::RateCards::Schedule))
      )
      expect(BillingOperation.count).to eq(0)
    end
  end

  context "when the card has no periodic action" do
    let(:product) { create(:product, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "advance", display_on_invoice: true) }

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_call_original
      allow(ContractRateCards::ResetBillingClockService).to receive(:call!).and_call_original
    end

    it "uses the reset path when no reconciliation is needed" do
      expect(contract_rate_card.periodic_billing_action).to be_nil
      result
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::Schedule::BuildPlannedOperation).to have_received(:call!).with(hash_including(timestamp: effective_from)).at_least(:once)
      expect(ContractRateCards::ResetBillingClockService).to have_received(:call!).with(
        hash_including(contract_rate_card:, schedule: instance_of(Billing::RateCards::Schedule))
      )
    end
  end

  context "with purchased advance coverage" do
    let(:billing_timing) { "advance" }
    let(:planned_operations) { [] }
    let(:advance_activation_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "renew_fixed_advance", causation_type: "contract_activation",
        billing_at: contract.started_at, target_cycle_started_at: contract.started_at)
    end
    let(:initialize_clock) do
      ContractRateCards::ResetBillingClockService.call!(contract_rate_card:, timestamp: contract.started_at).tap do
        advance_activation_operation
        BillingOperations::ProcessService.call!(customer:, timestamp: Time.utc(2026, 11, 1))
        contract_rate_card.update!(next_billing_at: effective_from)
      end
    end

    before do
      allow(BillingOperations::Schedule::BuildPlannedOperation).to receive(:call!).and_wrap_original do |original, **attributes|
        original.call(**attributes).tap do |plan_result|
          planned_operations << plan_result.planned_operation unless attributes.key?(:schedule)
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
        target_cycle_started_at: planned_operations.sole.cycle_started_at
      )
      expect(contract_rate_card.reload.next_billing_at).to eq(effective_from)
      expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id).once
      expect { described_class.call!(customer:, rate_card_rate_id: new_rate.id) }.to change(BillingOperation, :count).by(1)
      expect(reconciliation.reload.processed_at).to be_nil
      expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id).twice
    end
  end
end
