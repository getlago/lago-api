# frozen_string_literal: true

require "rails_helper"

describe Clock::RetryPendingViesChecksJob, job: true do
  subject(:retry_job) { described_class }

  let(:organization) { create(:organization) }
  let(:billing_entity) { create(:billing_entity, organization:, eu_tax_management:) }
  let(:eu_tax_management) { true }
  let(:customer) { create(:customer, organization:, billing_entity:, tax_identification_number: "IT12345678901", deleted_at:) }
  let(:deleted_at) { nil }
  let(:pending_vies_check) { create(:pending_vies_check, customer:, updated_at:) }
  let(:updated_at) { (described_class::STALE_AFTER + 1.minute).ago }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    before do
      freeze_time
      pending_vies_check
    end

    context "when the pending check has not been touched for longer than the max retry delay" do
      it "enqueues a VIES check for the customer" do
        retry_job.perform_now

        expect(Customers::ViesCheckJob).to have_been_enqueued.with(customer)
      end
    end

    context "when the pending check was never attempted" do
      let(:pending_vies_check) do
        create(:pending_vies_check, customer:, attempts_count: 0, last_attempt_at: nil, last_error_type: nil, updated_at:)
      end

      it "enqueues a VIES check for the customer" do
        retry_job.perform_now

        expect(Customers::ViesCheckJob).to have_been_enqueued.with(customer)
      end
    end

    context "when the pending check was touched within the stale threshold" do
      let(:updated_at) { (described_class::STALE_AFTER - 1.minute).ago }

      it "does not enqueue a VIES check" do
        retry_job.perform_now

        expect(Customers::ViesCheckJob).not_to have_been_enqueued
      end
    end

    context "when the billing entity no longer manages EU taxes" do
      let(:eu_tax_management) { false }

      it "does not enqueue a VIES check" do
        retry_job.perform_now

        expect(Customers::ViesCheckJob).not_to have_been_enqueued
      end
    end

    context "when the customer moved to a billing entity without EU tax management" do
      let(:eu_tax_management) { false }
      let(:previous_billing_entity) { create(:billing_entity, organization:, eu_tax_management: true) }
      let(:pending_vies_check) { create(:pending_vies_check, customer:, billing_entity: previous_billing_entity, updated_at:) }

      it "does not enqueue a VIES check" do
        retry_job.perform_now

        expect(Customers::ViesCheckJob).not_to have_been_enqueued
      end
    end

    context "when the customer is deleted" do
      let(:deleted_at) { 1.day.ago }

      it "does not enqueue a VIES check" do
        retry_job.perform_now

        expect(Customers::ViesCheckJob).not_to have_been_enqueued
      end
    end
  end
end
