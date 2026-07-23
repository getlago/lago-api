# frozen_string_literal: true

require "rails_helper"

# Regression test for the subscription-termination timing issue.
#
# Previously, Clock::TerminateEndedSubscriptionsJob matched subscriptions by
# comparing calendar DATES (DATE(ending_at) = DATE(now)), so a subscription with
# `ending_at` at 15:00 was terminated by the midnight run — several hours BEFORE
# it actually ended, leaving the customer without a subscription in between.
#
# The job now compares timestamps (ending_at <= now) and runs hourly, so a
# subscription is only terminated once its `ending_at` instant has passed.
describe "Subscription is not terminated before its ending time" do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: "") }

  # Use UTC to isolate the timestamp behaviour from any timezone shifting.
  let(:timezone) { "UTC" }
  let(:customer) { create(:customer, organization:, timezone:) }

  let(:plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 1000,
      pay_in_advance: false
    )
  end

  let(:creation_time)  { Time.zone.parse("2023-09-05T00:00:00") }
  let(:subscription_at) { Time.zone.parse("2023-09-05T00:00:00") }

  # Subscription is supposed to end at 15:00 UTC on 2023-09-06.
  let(:ending_at) { Time.zone.parse("2023-09-06T15:00:00") }

  it "keeps the subscription active at midnight and terminates it after ending_at" do
    subscription = nil

    travel_to(creation_time) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601,
          ending_at: ending_at.iso8601
        }
      )

      subscription = customer.subscriptions.first
      expect(subscription).to be_active
    end

    # Midnight run on the ending day: ending_at (15:00) has NOT passed yet,
    # so the subscription must stay active — no early termination, no gap.
    travel_to(Time.zone.parse("2023-09-06T00:05:00")) do
      Clock::TerminateEndedSubscriptionsJob.perform_now
      perform_all_enqueued_jobs

      subscription.reload
      expect(subscription).to be_active
      expect(subscription).not_to be_terminated
      expect(subscription.terminated_at).to be_nil
    end

    # First hourly run after ending_at: now the subscription is terminated,
    # and terminated_at is at/after ending_at (never before it).
    travel_to(Time.zone.parse("2023-09-06T15:05:00")) do
      Clock::TerminateEndedSubscriptionsJob.perform_now
      perform_all_enqueued_jobs

      subscription.reload
      expect(subscription).to be_terminated
      expect(subscription.terminated_at).to be >= subscription.ending_at
    end
  end
end
