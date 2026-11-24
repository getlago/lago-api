# frozen_string_literal: true

require "rails_helper"

describe Clock::ProcessBillingOperationsJob, job: true do
  subject(:perform_job) { described_class.perform_now }

  let(:organization) { create(:organization) }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }

    before { described_class.unlock! }
    after { described_class.unlock! }
  end

  context "when only a reconciliation is due" do
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, organization:, customer:, started_at: 1.month.ago) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }
    let(:reconciliation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
        billing_at: 1.minute.ago, target_cycle_started_at: 1.month.ago)
    end

    before { reconciliation }

    it "leaves it pending without repeatedly dispatching the customer" do
      perform_job
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(customer.id)
      expect(reconciliation.reload.processed_at).to be_nil
    end
  end

  context "with a saved due renewal" do
    let(:timestamp) { Time.utc(2026, 11, 15) }
    let(:customer) { create(:customer, organization:, timezone: "UTC") }
    let(:contract) { create(:contract, organization:, customer:, started_at: timestamp) }
    let(:rate_card) { create(:rate_card, :advance, organization:, product: create(:product, :fixed, organization:)) }
    let(:rate) { create(:rate_card_rate, organization:, rate_card:, effective_from: timestamp) }
    let(:card) do
      create(:contract_rate_card, organization:, contract:, rate_card:, effective_date: timestamp.to_date,
        billing_anchor_date: timestamp.to_date, next_billing_at: timestamp + 1.month)
    end
    let(:operation) { create(:billing_operation, :with_plan, organization:, customer:, contract_rate_card: card, billing_at: timestamp, coverage_started_at: timestamp) }

    around { |example| travel_to(timestamp + 5.minutes) { example.run } }

    before do
      rate
      operation
    end

    shared_examples "processing the saved renewal" do
      it "wakes for the saved operation and processes it exactly once across two clock ticks" do
        segments = operation.segments.map(&:attributes)
        BillingOperations::ApplyRateChangeJob.perform_now(customer.id, rate.id)
        expect(card.reload.next_billing_at).to eq(timestamp)

        2.times do
          perform_enqueued_jobs(only: BillingOperations::ProcessJob) { described_class.perform_now }
          perform_enqueued_jobs { Clock::ScheduleBillingOperationsJob.perform_now }
        end
        expect(card.billing_operations.periodic.sole).to eq(operation)
        expect(operation.reload.processed_at).to be_present
        expect(operation.segments.map(&:attributes)).to eq(segments)
        expect(customer.invoices.sole.id).to eq(operation.invoice_id)
        expect(card.reload.next_billing_at).to eq(next_wake)
      end
    end

    context "when the live rate moves later" do
      let(:next_wake) { timestamp + 1.month }

      before { rate.update!(effective_from: timestamp + 2.days) }

      include_examples "processing the saved renewal"
    end

    context "when the last rate was discarded" do
      let(:next_wake) { nil }

      before { rate.discard! }

      include_examples "processing the saved renewal"
    end
  end

  context "with saved periodic work" do
    let(:customer) { create(:customer, organization:) }
    let(:future_customer) { create(:customer, organization:) }
    let(:pending_customer) { create(:customer, organization:) }
    let(:deleted_customer) { create(:customer, organization:, deleted_at: 1.day.ago) }
    let(:terminated_contract) { create(:contract, :terminated, organization:, customer:) }
    let(:future_contract) { create(:contract, organization:, customer: future_customer) }
    let(:pending_contract) { create(:contract, :pending, organization:, customer: pending_customer, started_at: 1.month.ago) }
    let(:deleted_contract) { create(:contract, organization:, customer: deleted_customer) }

    before do
      [
        [terminated_contract, 1.day.ago],
        [future_contract, 1.day.from_now],
        [pending_contract, 1.day.ago],
        [deleted_contract, 1.day.ago]
      ].each do |contract, billing_at|
        card = create(:contract_rate_card, organization:, contract:, next_billing_at: 1.month.from_now)
        create(:billing_operation, organization:, customer: contract.customer, contract_rate_card: card, billing_at:)
      end
    end

    it "dispatches owed work even after termination, but excludes future and pending contracts" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ProcessJob).with(customer.id).exactly(1).times
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(future_customer.id)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(pending_customer.id)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(deleted_customer.id)
    end
  end

  context "when completion committed but invoice finalization failed" do
    let(:customer) { create(:customer, organization:) }
    let(:contract) { create(:contract, organization:, customer:) }
    let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:, next_billing_at: 1.month.from_now) }
    let(:invoice) { create(:invoice, organization:, customer:, invoice_type: :contract, status: :generating) }

    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, invoice:, processed_at: Time.current)
    end

    it "does not wake the processor solely for a linked generating invoice" do
      expect { perform_job }.not_to have_enqueued_job(BillingOperations::ProcessJob)
      expect(invoice.reload).to be_generating
    end
  end
end
