# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingOperations::ScheduleJob, job: true do
  subject(:perform_job) { described_class.perform_now(customer.id) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:) }
  let(:contract_rate_card) { create(:contract_rate_card, organization:, contract:) }

  it_behaves_like "a unique job" do
    let(:job_args) { [customer.id] }

    before { described_class.unlock! }
    after { described_class.unlock! }
  end

  before do
    allow(BillingOperations::ScheduleService).to receive(:call!).with(customer:).and_call_original
  end

  context "when due pending operations exist" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago)
    end

    before { operation }

    it "schedules the customer and dispatches processing" do
      expect { perform_job }.to have_enqueued_job(BillingOperations::ProcessJob).with(customer.id)
      expect(BillingOperations::ScheduleService).to have_received(:call!).with(customer:)
      expect(operation.reload).to have_attributes(processed_at: nil, cancelled_at: nil)
    end
  end

  context "when the customer has no due pending operations" do
    let(:future_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.day.from_now)
    end
    let(:processed_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago,
        processed_at: Time.current)
    end
    let(:cancelled_operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago,
        cancelled_at: Time.current, cancelled_causation_type: :rate_change)
    end
    let(:other_customer) { create(:customer, organization:) }
    let(:other_contract) { create(:contract, organization:, customer: other_customer) }
    let(:other_rate_card) { create(:contract_rate_card, organization:, contract: other_contract) }
    let(:other_customer_operation) do
      create(:billing_operation, organization:, customer: other_customer, contract_rate_card: other_rate_card,
        billing_at: 1.minute.ago)
    end

    before do
      future_operation
      processed_operation
      cancelled_operation
      other_customer_operation
    end

    it "does not dispatch processing for the customer" do
      expect { perform_job }.not_to have_enqueued_job(BillingOperations::ProcessJob)
    end
  end

  context "when scheduling fails" do
    let(:operation) do
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: 1.minute.ago)
    end
    let(:failure) { BaseService::Result.new.single_validation_failure!(field: :base, error_code: "cannot_schedule") }

    before do
      operation
      allow(BillingOperations::ScheduleService).to receive(:call!).with(customer:)
        .and_raise(BaseService::FailedResult.new(failure, "cannot schedule"))
    end

    it "does not dispatch processing" do
      expect { perform_job }.to raise_error(BaseService::FailedResult)
      expect(BillingOperations::ProcessJob).not_to have_been_enqueued
    end
  end
end
