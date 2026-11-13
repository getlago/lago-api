# frozen_string_literal: true

require "rails_helper"

describe Clock::ProcessBillingOperationsJob, job: true do
  subject(:perform_job) { described_class.perform_now }

  let(:organization) { create(:organization) }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe "due pending operations" do
    let(:due_customer) { create(:customer, organization:) }
    let(:future_customer) { create(:customer, organization:) }
    let(:processed_customer) { create(:customer, organization:) }
    let(:cancelled_customer) { create(:customer, organization:) }

    before do
      [
        [due_customer, {billing_at: Time.current - 1.minute}],
        [future_customer, {billing_at: Time.current + 1.day}],
        [processed_customer, {billing_at: Time.current - 1.minute, processed_at: Time.current}],
        [cancelled_customer, {
          billing_at: Time.current - 1.minute, cancelled_at: Time.current,
          cancelled_causation_type: :contract_termination
        }]
      ].each do |customer, attributes|
        contract = create(:contract, organization:, customer:, started_at: 1.month.ago)
        card = create(:contract_rate_card, organization:, contract:)
        create(:billing_operation, organization:, customer:, contract_rate_card: card,
          target_cycle_started_at: Time.current.beginning_of_month - 1.month, **attributes)
      end
    end

    it "enqueues one job for each customer with due pending operations" do
      perform_job

      expect(BillingOperations::ProcessJob).to have_been_enqueued.with(due_customer.id).once
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(future_customer.id)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(processed_customer.id)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(cancelled_customer.id)
    end
  end

  context "when several operations are due for one customer" do
    let(:customer) { create(:customer, organization:) }

    before do
      2.times do
        contract = create(:contract, organization:, customer:, started_at: 1.month.ago)
        card = create(:contract_rate_card, organization:, contract:)
        create(:billing_operation, organization:, customer:, contract_rate_card: card,
          billing_at: Time.current - 1.minute,
          target_cycle_started_at: Time.current.beginning_of_month - 1.month)
      end
    end

    it "enqueues the customer only once" do
      perform_job

      expect(BillingOperations::ProcessJob).to have_been_enqueued.with(customer.id).once
    end
  end

  context "when the customer is discarded" do
    let(:customer) { create(:customer, organization:) }

    before do
      contract = create(:contract, organization:, customer:, started_at: 1.month.ago)
      card = create(:contract_rate_card, organization:, contract:)
      create(:billing_operation, organization:, customer:, contract_rate_card: card,
        billing_at: Time.current - 1.minute,
        target_cycle_started_at: Time.current.beginning_of_month - 1.month)
      customer.discard!
    end

    it "leaves the customer out" do
      perform_job

      expect(BillingOperations::ProcessJob).not_to have_been_enqueued.with(customer.id)
    end
  end
end
