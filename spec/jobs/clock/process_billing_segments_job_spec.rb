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
    def segment(customer, status, product: create(:product, :fixed, organization:))
      rate_card = create(:rate_card, organization:, product:)
      contract = create(:contract, organization:, customer:, started_at: 1.month.ago)
      contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card:)

      create(:billing_segment, organization:, customer:, contract:, contract_rate_card:, status:)
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

    # The fan-out is per customer, not per segment: a customer with several pending segments
    # is invoiced by one run, and the consumer groups them itself.
    context "when a customer holds several pending segments" do
      before { segment(waiting_customer, :pending) }

      it "enqueues that customer once" do
        described_class.perform_now

        expect(BillingSegments::ProcessJob).to have_been_enqueued.with(waiting_customer.id).once
      end
    end

    # Both unbilled states, not just pending: the consumer selects its segments by the same
    # scope, so a customer offered here is always a customer it has work for.
    context "when a customer's segments are processing" do
      let(:claimed_customer) { create(:customer, organization:) }

      before { segment(claimed_customer, :processing) }

      it "enqueues that customer" do
        described_class.perform_now

        expect(BillingSegments::ProcessJob).to have_been_enqueued.with(claimed_customer.id)
      end
    end

    # Deleting a customer leaves their segments pending, so without this the scan keeps
    # enqueueing them and the job raises RecordNotFound loading the customer back:
    # BillingSegment#customer is with_discarded, Customer's own default scope is not.
    context "when the customer has been deleted" do
      let(:deleted_customer) { create(:customer, organization:) }

      before do
        segment(deleted_customer, :pending)
        deleted_customer.discard!
      end

      it "leaves them out" do
        described_class.perform_now

        expect(BillingSegments::ProcessJob).not_to have_been_enqueued.with(deleted_customer.id)
      end
    end

    # Metered usage billed in advance is priced per event, so the consumer skips those
    # segments and they never leave their state. Offering the customer anyway would enqueue
    # a run with nothing to do, every hour, for good.
    context "when the only pending segment is metered and billed in advance" do
      let(:streaming_customer) { create(:customer, organization:) }
      let(:metered_product) { create(:product, organization:, billable_metric: create(:billable_metric, organization:)) }

      before do
        rate_card = create(:rate_card, organization:, product: metered_product, billing_timing: "advance")
        contract = create(:contract, organization:, customer: streaming_customer, started_at: 1.month.ago)
        contract_rate_card = create(:contract_rate_card, organization:, contract:, rate_card:)

        create(
          :billing_segment,
          organization:,
          customer: streaming_customer,
          contract:,
          contract_rate_card:,
          status: :pending
        )
      end

      it "leaves that customer out" do
        described_class.perform_now

        expect(BillingSegments::ProcessJob).not_to have_been_enqueued.with(streaming_customer.id)
      end
    end
  end
end
