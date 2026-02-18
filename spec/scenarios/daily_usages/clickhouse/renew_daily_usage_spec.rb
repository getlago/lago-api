# frozen_string_literal: true

require "rails_helper"

describe "Daily Usage Renewal Flag Scenario (Clickhouse)", :premium, cache: :redis, clickhouse: true, transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, premium_integrations:, clickhouse_events_store: true) }
  let(:premium_integrations) { %w[revenue_analytics lifetime_usage] }
  let(:plan) { create(:plan, organization:, name: "Test Plan", code: "test_plan", amount_cents: 10_00) }
  let(:customer) { create(:customer, external_id: "cust_daily_usage_ch", organization:) }

  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "ops", field_name: "ops_count") }
  let(:charge) { create(:standard_charge, billable_metric:, plan:, amount_currency: "EUR", properties: {amount: "5"}) }

  let(:subscription_external_id) { "sub_daily_usage_ch" }

  def send_event!(params)
    create_event({
      transaction_id: "tr_#{SecureRandom.hex(16)}"
    }.merge(params))
  end

  before { charge }

  it "toggles renew_daily_usage flag through event lifecycle" do
    travel_to(DateTime.new(2025, 1, 1)) do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: subscription_external_id,
        plan_code: plan.code
      })
    end

    subscription = customer.subscriptions.sole
    expect(subscription.renew_daily_usage).to be(false)

    # Sending an event triggers TrackSubscriptionActivityService which sets renew_daily_usage to true
    travel_to(DateTime.new(2025, 1, 5, 12, 0, 0)) do
      send_event!(code: billable_metric.code, properties: {ops_count: 10}, external_subscription_id: subscription_external_id)
    end

    subscription.reload
    expect(subscription.renew_daily_usage).to be(true)

    # Running ComputeAllDailyUsages + ComputeService resets the flag to false
    travel_to(DateTime.new(2025, 1, 6, 0, 5, 0)) do
      perform_usage_update
    end

    subscription.reload
    expect(subscription.renew_daily_usage).to be(false)

    # Sending another event sets the flag to true again
    travel_to(DateTime.new(2025, 1, 6, 14, 0, 0)) do
      send_event!(code: billable_metric.code, properties: {ops_count: 5}, external_subscription_id: subscription_external_id)
    end

    subscription.reload
    expect(subscription.renew_daily_usage).to be(true)

    # Running usage update again resets the flag
    travel_to(DateTime.new(2025, 1, 7, 0, 5, 0)) do
      perform_usage_update
    end

    subscription.reload
    expect(subscription.renew_daily_usage).to be(false)

    # Without new events, the flag stays false
    travel_to(DateTime.new(2025, 1, 8, 0, 5, 0)) do
      perform_usage_update
    end

    subscription.reload
    expect(subscription.renew_daily_usage).to be(false)
  end
end
