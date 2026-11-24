# frozen_string_literal: true

require "rails_helper"

describe Clock::ScheduleBillingOperationsJob, job: true do
  subject(:perform_job) { described_class.perform_now }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, started_at: 1.month.ago) }
  let(:due_rate_cards) { create_list(:contract_rate_card, 2, organization:, contract:, next_billing_at: 1.minute.ago) }
  let(:future_customer) { create(:customer, organization:) }
  let(:future_contract) { create(:contract, organization:, customer: future_customer, started_at: 1.month.ago) }
  let(:future_rate_card) do
    create(:contract_rate_card, organization:, contract: future_contract, next_billing_at: 1.day.from_now)
  end

  before do
    due_rate_cards.each { create(:rate_card_rate, organization:, rate_card: it.rate_card) }
    create(:rate_card_rate, organization:, rate_card: future_rate_card.rate_card)
  end

  it_behaves_like "a unique job" do
    let(:job_args) { [] }

    before { described_class.unlock! }
    after { described_class.unlock! }
  end

  it "enqueues one scheduling job per customer with due cards" do
    expect { perform_job }.to have_enqueued_job(BillingOperations::ScheduleJob).with(customer.id).exactly(1).times
    expect(BillingOperations::ScheduleJob).not_to have_been_enqueued.with(future_customer.id)
  end

  context "when a units adjustment is pending before the next periodic billing" do
    let(:processed_at) { nil }
    let(:action_type) { "adjust_fixed_advance" }

    before do
      create(:billing_operation, organization:, customer: future_customer, contract_rate_card: future_rate_card,
        action_type:, reason: "contract_units_change", billing_at: 1.minute.ago, processed_at:)
    end

    it "recovers the adjustment without waiting for the periodic cursor" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ScheduleJob).with(future_customer.id).exactly(1).times
    end

    context "when the adjustment is already complete" do
      let(:processed_at) { 30.seconds.ago }

      it "does not dispatch completed work" do
        perform_job
        expect(BillingOperations::ScheduleJob).not_to have_been_enqueued.with(future_customer.id)
      end
    end

    context "when the operation is deferred rate-change reconciliation" do
      let(:action_type) { "reconcile_advance_coverage" }

      it "does not dispatch unsupported reconciliation" do
        perform_job
        expect(BillingOperations::ScheduleJob).not_to have_been_enqueued.with(future_customer.id)
      end
    end
  end
end
