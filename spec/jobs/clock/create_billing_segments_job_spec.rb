# frozen_string_literal: true

require "rails_helper"

describe Clock::CreateBillingSegmentsJob, job: true do
  subject { described_class }

  let(:organization) { create(:organization) }
  let(:due_customer) { create(:customer, organization:) }
  let(:quiet_customer) { create(:customer, organization:) }

  it_behaves_like "a unique job" do
    let(:job_args) { [] }
  end

  describe ".perform" do
    # Priced: a rate card without a rate is not due, which the scope's own spec covers.
    def priced_card(customer, next_billing_at)
      rate_card = create(:rate_card, organization:)
      create(:rate_card_rate, organization:, rate_card:)

      create(
        :contract_rate_card,
        organization:,
        rate_card:,
        contract: create(:contract, organization:, customer:, started_at: 1.month.ago),
        next_billing_at:
      )
    end

    before do
      priced_card(due_customer, 1.day.ago)
      priced_card(quiet_customer, 1.month.from_now)
    end

    it "enqueues one job for each customer with a due card" do
      described_class.perform_now

      expect(BillingSegments::ScheduleJob).to have_been_enqueued.with(due_customer.id)
    end

    it "leaves out a customer with nothing due" do
      described_class.perform_now

      expect(BillingSegments::ScheduleJob).not_to have_been_enqueued.with(quiet_customer.id)
    end
  end
end
