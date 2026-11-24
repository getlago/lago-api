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
