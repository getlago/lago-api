# frozen_string_literal: true

require "rails_helper"

describe Clock::ProcessBillingSegmentsJob, job: true do
  subject { described_class }

  let(:organization) { create(:organization) }
  let(:owed_customer) { create(:customer, organization:) }
  let(:settled_customer) { create(:customer, organization:) }
  let(:processing_customer) { create(:customer, organization:) }
  let(:future_processing_customer) { create(:customer, organization:) }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    before do
      create(:billing_segment, organization:, customer: owed_customer)
      create(:billing_segment, organization:, customer: settled_customer, status: :done)
      create(:billing_segment, organization:, customer: processing_customer, status: :processing, ended_at: 1.second.ago)
      create(:billing_segment, organization:, customer: future_processing_customer, status: :processing, ended_at: 1.day.from_now)
    end

    it "enqueues a customer whose processing segment has closed" do
      described_class.perform_now

      expect(BillingSegments::ProcessJob).to have_been_enqueued.with(processing_customer.id)
    end

    it "enqueues a customer whose processing segment is still open" do
      described_class.perform_now

      expect(BillingSegments::ProcessJob).to have_been_enqueued.with(future_processing_customer.id)
    end

    it "enqueues one job for each customer holding a pending segment" do
      described_class.perform_now

      expect(BillingSegments::ProcessJob).to have_been_enqueued.with(owed_customer.id)
    end

    it "leaves out a customer whose segments are all settled" do
      described_class.perform_now

      expect(BillingSegments::ProcessJob).not_to have_been_enqueued.with(settled_customer.id)
    end

    # A customer with several pending segments is one invoice run, not one per segment.
    it "enqueues a customer once however many segments are pending" do
      create(:billing_segment, organization:, customer: owed_customer, cycle_started_at: 2.months.ago)

      described_class.perform_now

      expect(BillingSegments::ProcessJob).to have_been_enqueued.with(owed_customer.id).once
    end
  end
end
