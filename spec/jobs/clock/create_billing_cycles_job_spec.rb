# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::CreateBillingCyclesJob do
  subject(:job) { described_class }

  let!(:due) { create(:subscription_product_item, next_billing_at: 1.day.ago) }
  let!(:not_due) { create(:subscription_product_item, next_billing_at: 1.day.from_now) }
  let!(:ended) do
    create(:subscription_product_item, next_billing_at: 1.day.ago, started_at: 2.days.ago, ended_at: 1.hour.ago)
  end

  it "enqueues a schedule job only for due, active items" do
    job.perform_now

    expect(BillingCycles::ScheduleJob).to have_been_enqueued.with(due)
    expect(BillingCycles::ScheduleJob).not_to have_been_enqueued.with(not_due)
    expect(BillingCycles::ScheduleJob).not_to have_been_enqueued.with(ended)
  end
end
