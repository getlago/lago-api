# frozen_string_literal: true

require "rails_helper"

describe Clock::ProcessBillingSegmentsJob, job: true do
  subject { described_class }

  let(:organization) { create(:organization) }
  let(:waiting_customer) { create(:customer, organization:) }
  let(:settled_customer) { create(:customer, organization:) }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    def segment(customer, status)
      contract = create(:contract, organization:, customer:, started_at: 1.month.ago)

      create(:billing_segment, organization:, customer:, contract:, status:)
    end

    before do
      segment(waiting_customer, :pending)
      segment(settled_customer, :done)
    end

    it "enqueues one job for each customer holding a pending segment" do
      described_class.perform_now

      expect(BillingSegments::ProcessJob).to have_been_enqueued.with(waiting_customer.id)
    end

    it "leaves out a customer whose segments are all settled" do
      described_class.perform_now

      expect(BillingSegments::ProcessJob).not_to have_been_enqueued.with(settled_customer.id)
    end

    # Deleting a customer leaves their segments pending, so without this the scan keeps
    # enqueueing them and the job raises RecordNotFound loading the customer back:
    # BillingSegment#customer is with_discarded, Customer's own default scope is not.
    it "leaves out a deleted customer" do
      deleted = create(:customer, organization:)
      segment(deleted, :pending)
      deleted.discard!

      described_class.perform_now

      expect(BillingSegments::ProcessJob).not_to have_been_enqueued.with(deleted.id)
    end

    # The fan-out is per customer, not per segment: a customer with several pending segments
    # is invoiced by one run, and the consumer groups them itself.
    it "enqueues a customer once however many segments are pending" do
      segment(waiting_customer, :pending)

      described_class.perform_now

      expect(BillingSegments::ProcessJob).to have_been_enqueued.with(waiting_customer.id).once
    end
  end
end
