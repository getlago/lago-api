# frozen_string_literal: true

require "rails_helper"

describe "Daily Usage last_received_event_on Scenario", :premium, cache: :redis do
  let(:organization) { create(:organization, webhook_url: nil, premium_integrations:) }
  let(:premium_integrations) { %w[revenue_analytics lifetime_usage] }
  let(:plan) { create(:plan, organization:, name: "Test Plan", code: "test_plan", amount_cents: 10_00) }
  let(:customer) { create(:customer, external_id: "cust_daily_usage", organization:) }

  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "ops", field_name: "ops_count") }
  let(:charge) { create(:standard_charge, billable_metric:, plan:, amount_currency: "EUR", properties: {amount: "5"}) }

  let(:subscription_external_id) { "sub_daily_usage" }

  def send_event!(params)
    create_event({
      transaction_id: "tr_#{SecureRandom.hex(16)}"
    }.merge(params))
  end

  before { charge }

  it "tracks last_received_event_on through event lifecycle" do
    travel_to(DateTime.new(2025, 1, 1)) do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: subscription_external_id,
        plan_code: plan.code
      })
    end

    subscription = customer.subscriptions.sole
    expect(subscription.last_received_event_on).to be_nil

    # Sending an event sets last_received_event_on to today in customer's timezone
    travel_to(DateTime.new(2025, 1, 5, 12, 0, 0)) do
      send_event!(code: billable_metric.code, properties: {ops_count: 10}, external_subscription_id: subscription_external_id)
    end

    subscription.reload
    expect(subscription.last_received_event_on).to eq(Date.new(2025, 1, 5))

    # Running job at midnight same day (Jan 6 00:05 UTC) — queries for last_received_event_on = yesterday (Jan 5)
    # This matches! So daily usage for Jan 5 is computed.
    travel_to(DateTime.new(2025, 1, 6, 0, 5, 0)) do
      perform_usage_update
    end

    expect(DailyUsage.where(subscription:).count).to eq(1)

    # Sending another event updates the date
    travel_to(DateTime.new(2025, 1, 7, 14, 0, 0)) do
      send_event!(code: billable_metric.code, properties: {ops_count: 5}, external_subscription_id: subscription_external_id)
    end

    subscription.reload
    expect(subscription.last_received_event_on).to eq(Date.new(2025, 1, 7))
  end

  # Scenario: event arrives at 00:01 local time (just after midnight), job runs at 00:02.
  # The event belongs to the NEW day so the job looking for "yesterday" won't pick it up.
  # The next day's job run WILL process it.
  #
  # Using Asia/Kolkata (UTC+5:30) — a non-standard half-hour offset timezone.
  # 2025-01-05 18:31 UTC = 2025-01-06 00:01 IST → event date is Jan 6 in customer TZ
  # 2025-01-05 18:32 UTC = 2025-01-06 00:02 IST → job queries last_received_event_on = Jan 5 → no match (it's Jan 6)
  # 2025-01-06 18:32 UTC = 2025-01-07 00:02 IST → job queries last_received_event_on = Jan 6 → match!
  context "with tricky timezone and event at midnight boundary" do
    let(:customer) { create(:customer, external_id: "cust_daily_usage", organization:, timezone: "Asia/Kolkata") }

    it "defers midnight event to next day's daily usage computation" do
      travel_to(DateTime.new(2025, 1, 1)) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: subscription_external_id,
          plan_code: plan.code
        })
      end

      subscription = customer.subscriptions.sole

      # Send an earlier event on Jan 4 (IST) so there's something to compute
      # 2025-01-04 12:00 UTC = 2025-01-04 17:30 IST
      travel_to(Time.zone.parse("2025-01-04 12:00:00")) do
        send_event!(code: billable_metric.code, properties: {ops_count: 3}, external_subscription_id: subscription_external_id)
      end

      subscription.reload
      expect(subscription.last_received_event_on).to eq(Date.new(2025, 1, 4))

      # Job runs at 00:05 IST on Jan 5 (= 2025-01-04 18:35 UTC)
      # Queries last_received_event_on = Jan 4 (yesterday in IST) → match
      travel_to(Time.zone.parse("2025-01-04 18:35:00")) do
        perform_usage_update
      end

      expect(DailyUsage.where(subscription:).count).to eq(1)
      jan4_usage = DailyUsage.where(subscription:).last
      expect(jan4_usage.usage_date).to eq(Date.new(2025, 1, 4))

      # Event_a arrives at 00:01 IST on Jan 6 (= 2025-01-05 18:31 UTC)
      travel_to(Time.zone.parse("2025-01-05 18:31:00")) do
        send_event!(code: billable_metric.code, properties: {ops_count: 7}, external_subscription_id: subscription_external_id)
      end

      subscription.reload
      # last_received_event_on = Jan 6 (customer's local date)
      expect(subscription.last_received_event_on).to eq(Date.new(2025, 1, 6))

      # Job runs at 00:02 IST on Jan 6 (= 2025-01-05 18:32 UTC)
      # Queries last_received_event_on = Jan 5 (yesterday in IST)
      # But last_received_event_on is Jan 6 → NO match → subscription NOT selected
      travel_to(Time.zone.parse("2025-01-05 18:32:00")) do
        perform_usage_update
      end

      # No new daily usage was created for Jan 5
      expect(DailyUsage.where(subscription:, usage_date: Date.new(2025, 1, 5)).count).to eq(0)

      # Next day: job runs at 00:02 IST on Jan 7 (= 2025-01-06 18:32 UTC)
      # Queries last_received_event_on = Jan 6 → MATCH → subscription selected
      # Computes daily usage for Jan 6 which now includes event_a
      travel_to(Time.zone.parse("2025-01-06 18:32:00")) do
        perform_usage_update
      end

      jan6_usage = DailyUsage.where(subscription:, usage_date: Date.new(2025, 1, 6)).first
      expect(jan6_usage).to be_present
      # Jan 6 usage should include both events (3 + 7 = 10 ops_count → 50 amount_cents at rate "5")
      expect(jan6_usage.usage["amount_cents"]).to eq(5000)
    end
  end
end
