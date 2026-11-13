# frozen_string_literal: true

require "rails_helper"

RSpec.describe Contracts::TerminateService do
  subject(:result) { described_class.call(contract:) }

  let(:organization) { create(:organization, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:contract) { create(:contract, organization:, customer:, catalog_plan:) }

  before { allow(Utils::ActivityLog).to receive(:produce_after_commit) }

  it "terminates an active contract" do
    freeze_time do
      expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.terminated", contract)
      expect(result).to be_success
      expect(contract.reload).to have_attributes(status: "terminated", terminated_at: Time.current)
      expect(contract.canceled_at).to be_nil
      expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.terminated")
    end
  end

  # Started Aug 1 and terminated Aug 21 at 14:00, both in the customer's time: the termination
  # day is served, so a prorating card pays 21 of August's 31 days.
  context "when the contract has rate cards" do
    let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:started_at) { Time.find_zone("America/New_York").parse("2026-08-01 00:00:00") }
    let(:terminated_at) { Time.find_zone("America/New_York").parse("2026-08-21 14:00:00") }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:) }
    let(:arrears_card) { card(billing_timing: "arrears") }
    let(:advance_card) { card(billing_timing: "advance") }

    def card(billing_timing:, priced: true, proration: false)
      rate_card = create(:rate_card, organization:, billing_timing:, proration:, product: create(:product, :fixed, organization:))
      if priced
        create(:rate_card_rate, organization:, rate_card:, effective_from: started_at - 1.month, billing_interval_count: 1, billing_interval_unit: "month")
      end

      create(
        :contract_rate_card,
        organization:, contract:, rate_card:,
        effective_date: Date.new(2026, 8, 1),
        billing_anchor_date: Date.new(2026, 8, 1)
      )
    end

    def operations_of(card) = BillingOperation.where(contract_rate_card: card)

    before do
      arrears_card
      advance_card
      contract.applied_rate_cards.find_each do |card|
        ContractRateCards::ResetBillingClockService.call!(contract_rate_card: card, timestamp: contract.started_at)
      end
    end

    it "resets the cursor to the final arrears obligation" do
      travel_to(terminated_at) { result }

      expect(result).to be_success
      expect(arrears_card.reload.next_billing_at).to eq(terminated_at)
      expect(operations_of(arrears_card).sole).to have_attributes(
        action_type: "close_fixed_arrears", causation_type: "contract_termination",
        billing_at: contract.reload.terminated_at, target_cycle_started_at: started_at,
        processed_at: nil, invoice_id: nil
      )
      expect(LegacyBillingSegment.where(contract_rate_card_id: arrears_card.id)).to be_empty
    end

    context "when the arrears card prorates" do
      let(:arrears_card) { card(billing_timing: "arrears", proration: true) }

      it "persists the final close date for the prorated card" do
        travel_to(terminated_at) { result }

        expect(result).to be_success
        expect(operations_of(arrears_card).sole).to have_attributes(
          action_type: "close_fixed_arrears", causation_type: "contract_termination",
          billing_at: contract.reload.terminated_at, target_cycle_started_at: started_at
        )
      end
    end

    context "when the advance operation has already completed" do
      before { BillingOperations::ProcessService.call!(customer:, timestamp: started_at) }

      it "does not create another charge or change its completed operation" do
        previous = advance_card.billing_operations.sole.attributes

        expect { travel_to(terminated_at) { result } }.not_to change { advance_card.billing_operations.count }
        expect(advance_card.billing_operations.sole.attributes).to eq(previous)
        expect(LegacyBillingSegment.where(contract_rate_card_id: advance_card.id)).to be_empty
      end
    end

    it "does not create segments while scheduling the operation" do
      expect { travel_to(terminated_at) { result } }
        .not_to change(LegacyBillingSegment, :count)
    end

    it "enqueues due operation processing after termination commits" do
      expect { travel_to(terminated_at) { result } }
        .to have_enqueued_job_after_commit(BillingOperations::ProcessJob).with(customer.id)
    end

    context "when only overdue advance work remains" do
      let(:arrears_card) { card(billing_timing: "arrears", priced: false) }

      it "does not enqueue processing when no new termination operation is created" do
        expect { travel_to(terminated_at) { result } }
          .not_to have_enqueued_job(BillingOperations::ProcessJob)
        expect(advance_card.reload.next_billing_at).to eq(started_at)
        expect(advance_card.billing_operations).to be_empty
        expect(operations_of(arrears_card)).to be_empty
      end
    end

    # Time is not frozen here: a real clock carries nanoseconds the database drops, and the
    # final slice must still fall due at the instant stored.
    it "preserves the overdue cursor before continuing to the final coverage" do
      result

      expect(arrears_card.reload.next_billing_at).to eq(Time.find_zone("America/New_York").parse("2026-09-01 00:00:00"))
      expect(operations_of(arrears_card)).to be_empty
    end

    context "when a card has no price yet" do
      let(:unpriced_card) { card(billing_timing: "arrears", priced: false) }

      before { unpriced_card }

      it "terminates without billing it" do
        travel_to(terminated_at) { result }

        expect(result).to be_success
        expect(operations_of(unpriced_card)).to be_empty
        expect(LegacyBillingSegment.where(contract_rate_card_id: unpriced_card.id)).to be_empty
      end
    end

    context "when closing the billing fails" do
      before do
        allow(BillingOperations::TerminateService).to receive(:call!)
          .and_raise(BaseService::ValidationFailure.new(BaseResult.new, messages: {billing_operation: ["value_is_invalid"]}))
      end

      it "leaves the contract active" do
        expect(result.error.messages).to eq({billing_operation: ["value_is_invalid"]})
        expect(contract.reload.status).to eq("active")
      end
    end

    context "when the clock holds the customer's billing lock" do
      before do
        allow(Customers::LockService).to receive(:call).and_raise(BaseLockService::FailedToAcquireLock)
      end

      it "reports the conflict and leaves the contract active" do
        expect(result.error).to be_a(BaseService::LockAcquisitionFailure)
        expect(contract.reload.status).to eq("active")
      end
    end
  end

  context "when a fixed advance successor starts later in the current cycle" do
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:started_at) { Time.utc(2026, 1, 1) }
    let(:terminated_at) { Time.utc(2026, 1, 10) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:, currency: "USD") }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:,
        effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
        rate_model: "standard", rate_properties: {"amount" => "10"},
        billing_interval_count: 1, billing_interval_unit: "month")
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 1, 15),
        rate_model: "standard", rate_properties: {"amount" => "20"},
        billing_interval_count: 1, billing_interval_unit: "month")
      contract_rate_card
      contract.applied_rate_cards.find_each do |card|
        ContractRateCards::ResetBillingClockService.call!(contract_rate_card: card, timestamp: contract.started_at)
      end
      BillingOperations::ProcessService.call!(customer:, timestamp: started_at)
    end

    it "clears the future renewal cursor without changing the issued invoice" do
      invoice = Invoice.where(customer:).sole
      invoice_attributes = invoice.attributes
      expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 1, 15))

      termination = described_class.call(contract:, timestamp: terminated_at)
      expect(termination).to be_success

      processed = BillingOperations::ProcessService.call!(customer:, timestamp: terminated_at)

      expect(processed.invoices).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to be_nil
      expect(contract_rate_card.billing_operations.where(causation_type: "contract_termination")).to be_empty
      expect(contract_rate_card.billing_operations.pending).to be_empty
      expect(contract_rate_card.billing_operations.count).to eq(1)
      expect(Invoice.where(customer:).pluck(:id)).to eq([invoice.id])
      expect(invoice.reload.attributes).to eq(invoice_attributes)
    end
  end

  context "when termination is scheduled several cycles ahead" do
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:started_at) { Time.utc(2026, 1, 1) }
    let(:timestamp) { Time.utc(2026, 4, 15) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:) }
    let(:billing_timing) { "arrears" }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing:, currency: "USD", proration: true) }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, units: 1,
        effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))
    end
    let(:original_cursor) { Time.utc(2026, 2, 1) }
    let(:amount_due_now) { 10_000 }

    before do
      travel_to(Time.utc(2026, 2, 10))
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
        rate_model: "standard", rate_properties: {"amount" => "100"},
        billing_interval_count: 1, billing_interval_unit: "month")
      contract_rate_card
      contract.applied_rate_cards.find_each do |card|
        ContractRateCards::ResetBillingClockService.call!(contract_rate_card: card, timestamp: contract.started_at)
      end
    end

    shared_examples "complete termination coverage" do
      it "preserves overdue work and bills each missing cycle once, only when due" do
        expect(described_class.call(contract:, timestamp:)).to be_success
        expect(contract_rate_card.reload.next_billing_at).to eq(original_cursor)
        expect(contract_rate_card.billing_operations).to be_empty

        BillingOperations::ProcessService.call!(customer:, timestamp: Time.current)
        expect(Invoice.where(customer:).sum(:total_amount_cents)).to eq(amount_due_now)
        expect(contract_rate_card.billing_operations.count).to eq(1)

        travel_to(timestamp) do
          3.times { BillingOperations::ProcessService.call!(customer:, timestamp:) }
          expect(Invoice.where(customer:).sum(:total_amount_cents)).to eq(30_000 + (10_000.to_d * 14 / 30).round)
          # Three full months plus April 1–15 (14 of April's 30 days).
          expect(contract_rate_card.billing_operations.pending).to be_empty
          expect(contract_rate_card.billing_operations.count).to eq(4)
          expect(BillingOperations::ProcessService.call!(customer:, timestamp:).invoices).to be_empty
        end
      end
    end

    it_behaves_like "complete termination coverage"

    it "does not enqueue processing when every obligation is still in the future" do
      travel_to(Time.utc(2026, 1, 10)) do
        expect { described_class.call(contract:, timestamp:) }
          .not_to have_enqueued_job(BillingOperations::ProcessJob)
      end
    end

    context "when billing in advance" do
      let(:billing_timing) { "advance" }
      let(:original_cursor) { Time.utc(2026, 1, 1) }
      let(:amount_due_now) { 10_000 }

      it_behaves_like "complete termination coverage"

      it "does not enqueue the preserved overdue renewal when no operation is created" do
        expect { described_class.call(contract:, timestamp:) }
          .not_to have_enqueued_job(BillingOperations::ProcessJob)
        expect(contract_rate_card.reload.next_billing_at).to eq(original_cursor)
      end
    end
  end

  context "when a monthly arrears contract ends halfway through November" do
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:started_at) { Time.utc(2026, 11, 1) }
    let(:terminated_at) { Time.utc(2026, 11, 15) }
    let(:contract) { create(:contract, organization:, customer:, catalog_plan:, started_at:) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:, billing_timing: "arrears", proration: true, currency: "USD") }
    let(:contract_rate_card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, units: 1,
        effective_date: Date.new(2026, 11, 1), billing_anchor_date: Date.new(2026, 11, 1))
    end
    let(:activation_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:,
        action_type: "close_fixed_arrears", causation_type: :contract_activation,
        billing_at: Time.utc(2026, 12, 1), target_cycle_started_at: started_at)
    end

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: started_at,
        rate_model: "standard", rate_properties: {"amount" => "30"},
        billing_interval_count: 1, billing_interval_unit: "month")
      contract_rate_card
      ContractRateCards::ResetBillingClockService.call!(
        contract_rate_card:, timestamp: started_at
      )
      activation_operation
    end

    it "dispatches the final operation after resetting the cursor" do
      travel_to(terminated_at) do
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 12, 1))
        expect { described_class.call(contract:, timestamp: terminated_at) }
          .to have_enqueued_job_after_commit(BillingOperations::ProcessJob).with(customer.id)

        operation = contract_rate_card.billing_operations.pending.sole
        expect(operation).to have_attributes(
          action_type: "close_fixed_arrears", billing_at: terminated_at,
          causation_type: "contract_termination", target_cycle_started_at: started_at,
          processed_at: nil, invoice_id: nil
        )
        expect(activation_operation.reload).to have_attributes(
          cancelled_at: terminated_at, cancelled_causation_type: "contract_termination"
        )
        expect(Invoice.where(customer:)).to be_empty
        expect(contract_rate_card.reload.next_billing_at).to eq(terminated_at)

        BillingOperations::ProcessService.call!(customer:, timestamp: terminated_at)

        expect(operation.reload).to have_attributes(processed_at: terminated_at)
        expect(Invoice.where(customer:).sum(:total_amount_cents)).to eq(1_400) # $30 * 14 / 30 days.
        expect(contract_rate_card.reload.next_billing_at).to be_nil
      end
    end

    it "discovers and processes the final operation when immediate dispatch is lost" do
      travel_to(terminated_at) do
        expect(described_class.call(contract:, timestamp: terminated_at)).to be_success
      end
      clear_enqueued_jobs

      processing_at = terminated_at + 17.minutes
      travel_to(processing_at) do
        perform_enqueued_jobs(only: [BillingOperations::ScheduleJob, BillingOperations::ProcessJob]) do
          Clock::ScheduleBillingOperationsJob.perform_now
        end
      end

      operation = contract_rate_card.billing_operations.find_by!(causation_type: :contract_termination)
      expect(activation_operation.reload).to have_attributes(
        cancelled_at: terminated_at, cancelled_causation_type: "contract_termination"
      )
      expect(operation).to have_attributes(processed_at: processing_at, cancelled_at: nil)
      expect(Invoice.where(customer:).sum(:total_amount_cents)).to eq(1_400) # $30 * 14 / 30 days.
      expect(contract_rate_card.reload.next_billing_at).to be_nil
    end
  end

  context "when given the instant it ends at" do
    subject(:result) { described_class.call(contract:, timestamp:) }

    let(:timestamp) { 1.hour.ago.change(usec: 0) }

    it "terminates it at that instant" do
      expect(result).to be_success
      expect(contract.reload.terminated_at).to eq(timestamp)
    end
  end

  context "when the clock activated the contract since it was loaded" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }

    before { Contract.where(id: contract.id).update_all(status: :active) } # rubocop:disable Rails/SkipsModelValidations

    it "terminates it instead of canceling it" do
      expect(result).to be_success
      expect(contract.reload.status).to eq("terminated")
    end
  end

  context "when the contract is pending" do
    let(:contract) { create(:contract, :pending, organization:, customer:, catalog_plan:) }
    let(:product) { create(:product, :fixed, organization:) }
    let(:rate_card) { create(:rate_card, organization:, product:) }
    let(:card) { create(:contract_rate_card, organization:, contract:, rate_card:) }

    it "cancels it instead of terminating" do
      freeze_time do
        expect { result }.to have_enqueued_job_after_commit(SendWebhookJob).with("contract.canceled", contract)
        expect(result).to be_success
        expect(contract.reload).to have_attributes(status: "canceled", canceled_at: Time.current)
        expect(contract.terminated_at).to be_nil
        expect(Utils::ActivityLog).to have_received(:produce_after_commit).with(contract, "contract.canceled")
      end
    end

    it "does not seed billing operations" do
      expect { result }.not_to change { card.billing_operations.count }
    end
  end

  context "when the contract is already terminated" do
    let(:contract) { create(:contract, :terminated, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.terminated", any_args)
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.canceled", any_args)
    end
  end

  context "when the contract is already canceled" do
    let(:contract) { create(:contract, :canceled, organization:, customer:, catalog_plan:) }

    it "rejects the termination" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result).not_to be_success
      expect(result.error.messages[:contract]).to eq(["cannot_terminate"])
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.terminated", any_args)
      expect(Utils::ActivityLog).not_to have_received(:produce_after_commit).with(anything, "contract.canceled", any_args)
    end
  end

  context "when the contract is missing" do
    let(:contract) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
