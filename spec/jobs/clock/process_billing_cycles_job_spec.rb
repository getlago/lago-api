# frozen_string_literal: true

require "rails_helper"

RSpec.describe Clock::ProcessBillingCyclesJob do
  subject(:job) { described_class }

  let(:billing_at) { Time.utc(2026, 7, 1) }
  let(:subscription_a) { create(:subscription) }
  let(:subscription_b) { create(:subscription) }

  # Two pending cycles for the same (subscription, billing_at) must collapse to one job.
  let!(:cycle_a1) { create(:billing_cycle, subscription: subscription_a, billing_at:) }
  let!(:cycle_a2) { create(:billing_cycle, subscription: subscription_a, billing_at:) }
  let!(:cycle_b) { create(:billing_cycle, subscription: subscription_b, billing_at:) }
  let!(:done_cycle) { create(:billing_cycle, status: :done) }

  it "enqueues one process job per pending (subscription, billing_at) group" do
    job.perform_now

    expect(BillingCycles::ProcessJob).to have_been_enqueued.with(subscription_a, billing_at).once
    expect(BillingCycles::ProcessJob).to have_been_enqueued.with(subscription_b, billing_at).once
    expect(BillingCycles::ProcessJob).to have_been_enqueued.exactly(:twice)
  end

  it "does not enqueue a job for cycles that are already done" do
    job.perform_now

    expect(BillingCycles::ProcessJob).not_to have_been_enqueued.with(done_cycle.subscription, done_cycle.billing_at)
  end
end
