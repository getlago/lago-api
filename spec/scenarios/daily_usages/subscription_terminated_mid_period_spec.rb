# frozen_string_literal: true

require "rails_helper"

# A subscription is terminated during a billing period. The daily usages written before the termination end
# at the end of the period, while the one written from the terminating invoice ends at the termination. They
# all accumulate usage from the start of the period, so summing the daily diffs gives the period's usage.
describe "Daily Usages: subscription terminated mid-period", :premium do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: [], premium_integrations: ["revenue_analytics"]) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "ops", field_name: "ops_count") }
  let(:plan) { create(:plan, organization:, interval: "monthly", amount_cents: 0, pay_in_advance: false) }
  let(:subscription) { customer.subscriptions.sole }

  before do
    create(:standard_charge, plan:, billable_metric:, properties: {amount: "10"})

    travel_to(DateTime.new(2025, 2, 1)) do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: "sub_terminated_mid_period",
        plan_code: plan.code,
        billing_time: "calendar"
      })
    end
  end

  def send_event(day)
    travel_to(DateTime.new(2025, 2, day, 12)) do
      create_event({code: billable_metric.code, external_subscription_id: subscription.external_id, properties: {ops_count: 1}})
    end
  end

  def compute_daily_usage(day)
    travel_to(DateTime.new(2025, 2, day + 1, 0, 10)) { perform_usage_update }
  end

  it "diffs the termination row against the rows written before it" do
    send_event(1)
    compute_daily_usage(1)
    send_event(2)
    compute_daily_usage(2)
    send_event(3)
    travel_to(DateTime.new(2025, 2, 3, 15)) { terminate_subscription(subscription) }

    rows = subscription.daily_usages.order(:usage_date).map do |daily_usage|
      [daily_usage.usage_date, daily_usage.to_datetime, daily_usage.usage["amount_cents"], daily_usage.usage_diff["amount_cents"]]
    end

    # One event a day of 1 op at 10 EUR: each day adds 1000 cents to the period's usage
    expect(rows).to eq([
      [Date.new(2025, 2, 1), Time.zone.parse("2025-02-28T23:59:59Z"), 1000, 1000],
      [Date.new(2025, 2, 2), Time.zone.parse("2025-02-28T23:59:59Z"), 2000, 1000],
      [Date.new(2025, 2, 3), Time.zone.parse("2025-02-03T15:00:00Z"), 3000, 1000]
    ])
  end

  it "diffs the termination row again when the daily job of the day before runs after it" do
    send_event(1)
    compute_daily_usage(1)
    send_event(2)
    travel_to(DateTime.new(2025, 2, 3, 0, 2)) do
      create_event({code: billable_metric.code, external_subscription_id: subscription.external_id, properties: {ops_count: 1}})
    end
    travel_to(DateTime.new(2025, 2, 3, 0, 5)) { terminate_subscription(subscription) }

    # The job scheduled at midnight for Feb 2 runs after the termination row is written, and reads up to the termination
    travel_to(DateTime.new(2025, 2, 3, 0, 20)) do
      DailyUsages::ComputeJob.perform_later(subscription, timestamp: DateTime.new(2025, 2, 3))
      perform_all_enqueued_jobs
    end

    rows = subscription.daily_usages.order(:usage_date).map do |daily_usage|
      [daily_usage.usage_date, daily_usage.usage["amount_cents"], daily_usage.usage_diff["amount_cents"]]
    end

    # The diffs add up to the 3000 cents of the period: the late row holds the events of Feb 2 and Feb 3
    expect(rows).to eq([
      [Date.new(2025, 2, 1), 1000, 1000],
      [Date.new(2025, 2, 2), 3000, 2000], # 3000 up to the termination - 1000 on Feb 1
      [Date.new(2025, 2, 3), 3000, 0] # 3000 at the termination - 3000 in the late row of Feb 2
    ])
  end
end
