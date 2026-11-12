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

  context "with periodic cursors" do
    let(:customer) { create(:customer, organization:) }
    let(:future_customer) { create(:customer, organization:) }
    let(:pending_customer) { create(:customer, organization:) }
    let(:terminated_contract) { create(:contract, :terminated, organization:, customer:) }
    let(:future_contract) { create(:contract, organization:, customer: future_customer) }
    let(:pending_contract) { create(:contract, :pending, organization:, customer: pending_customer) }

    before do
      create(:contract_rate_card, organization:, contract: terminated_contract, next_billing_at: 1.day.ago)
      create(:contract_rate_card, organization:, contract: future_contract, next_billing_at: 1.day.from_now)
      create(:contract_rate_card, organization:, contract: pending_contract, next_billing_at: 1.day.ago)
    end

    it "dispatches owed work even after termination, but excludes future and pending contracts" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ProcessJob).with(customer.id).exactly(1).times
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(future_customer.id)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(pending_customer.id)
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

    it "does not dispatch completed billing without a due cursor" do
      expect { perform_job }.not_to have_enqueued_job(BillingOperations::ProcessJob)
      expect(invoice.reload).to be_generating
    end
  end
end
