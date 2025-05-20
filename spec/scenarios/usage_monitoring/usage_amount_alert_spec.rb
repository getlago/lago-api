# frozen_string_literal: true

require "rails_helper"

describe "Subscriptions Alerting Scenario", :scenarios, type: :request, cache: :redis do
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:, name: "Premium Plan", code: "premium_plan", amount_cents: 49_00) }
  let(:customer) { create(:customer, external_id: "cust#{external_id}", organization:) }

  let(:billable_metric) { create(:sum_billable_metric, organization:, code: "ops", field_name: "ops_count") }
  let(:charge) { create(:standard_charge, billable_metric:, plan:, amount_currency: "EUR", properties: {amount: "5"}) }

  let(:bm_2) { create(:sum_billable_metric, organization:, code: "api", field_name: "api_count") }
  let(:charge_2) { create(:standard_charge, billable_metric: bm_2, plan:, amount_currency: "EUR", properties: {amount: "100"}) }

  let(:external_id) { "alerting-v1" }
  let(:subscription_external_id) { "sub_#{external_id}" }

  include_context "with webhook tracking"

  around { |test| lago_premium!(&test) }

  def send_event!(params)
    create_event({
      transaction_id: "tr_#{SecureRandom.hex(16)}"
    }.merge(params))
  end

  before do
    charge
    charge_2
  end

  it "monitors activity and trigger alerts" do
    create_subscription({
      external_customer_id: customer.external_id,
      external_id: subscription_external_id,
      plan_code: plan.code
    })
    subscription = customer.subscriptions.sole
    alert = UsageMonitoring::CreateAlertService.call!(
      organization:,
      subscription:,
      params: {alert_type: :usage_amount, code: :simple, thresholds: [
        {value: 15_00, code: :warn},
        {value: 30_00, code: :warn},
        {value: 50_00, code: :alert},
        {value: 1230_00, code: :block}
      ]}
    ).alert
    alert_on_bm = UsageMonitoring::CreateAlertService.call!(
      organization:,
      subscription:,
      params: {alert_type: :billable_metric_usage_amount, code: :bm, billable_metric: bm_2, thresholds: [
        {value: 399_00, code: :warn},
        {value: 1000_00, code: :alert}
      ]}
    ).alert

    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0
    send_event!(code: billable_metric.code, properties: {ops_count: 2}, external_subscription_id: subscription_external_id)
    # SubscriptionActivity is created by PostProcessEvents
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 1

    perform_usage_update

    expect(UsageMonitoring::TriggeredAlert.where(alert:).count).to eq(0)

    send_event!(code: billable_metric.code, properties: {ops_count: 2}, external_subscription_id: subscription_external_id)
    send_event!(code: billable_metric.code, properties: {ops_count: 2}, external_subscription_id: subscription_external_id)

    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 1
    perform_usage_update
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0

    ta = alert.triggered_alerts.sole
    expect(ta.current_value).to eq(3000)
    expect(ta.previous_value).to eq(1000)
    expect(ta.crossed_thresholds.map(&:symbolize_keys)).to eq([
      {code: "warn", value: "1500.0", recurring: false},
      {code: "warn", value: "3000.0", recurring: false}
    ])

    webhooks_sent.find { |w| w[:webhook_type] == "alert.triggered" }.tap do |webhook|
      expect(webhook[:object_type]).to eq("triggered_alert")
      expect(webhook[:triggered_alert]).to include({
        lago_id: ta.id,
        current_value: "3000.0",
        previous_value: "1000.0",
        triggered_at: String
      })
    end

    # WITH EVENTS ON CHARGE WITH SPECIAL ALERT
    send_event!(code: bm_2.code, properties: {api_count: 4}, external_subscription_id: subscription_external_id)
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 1
    perform_usage_update
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0

    expect(alert.triggered_alerts.count).to eq 2
    expect(alert_on_bm.triggered_alerts.count).to eq 1
    expect(webhooks_sent.count { |w| w.dig(:triggered_alert, :alert_type) == "usage_amount" }).to eq 2
    expect(webhooks_sent.count { |w| w.dig(:triggered_alert, :alert_type) == "billable_metric_usage_amount" }).to eq 1
  end

  context "with recurring thresholds" do
    it "sends alert forever" do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: subscription_external_id,
        plan_code: plan.code
      })
      subscription = customer.subscriptions.sole
      alert = UsageMonitoring::CreateAlertService.call!(
        organization:,
        subscription:,
        params: {alert_type: :usage_amount, code: "simple", thresholds: [
          {value: 15_00, code: :warn},
          {value: 30_00, code: :warn},
          {value: 10_00, code: :alert, recurring: true}
        ]}
      ).alert

      send_event!(code: billable_metric.code, properties: {ops_count: 7}, external_subscription_id: subscription_external_id)

      perform_usage_update
      expect(UsageMonitoring::TriggeredAlert.where(alert:).count).to eq(1)
      expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0

      ta = alert.triggered_alerts.sole
      expect(ta.current_value).to eq(3500)
      expect(ta.crossed_thresholds.map(&:symbolize_keys)).to eq([
        {code: "warn", value: "1500.0", recurring: false},
        {code: "warn", value: "3000.0", recurring: false}
      ])

      send_event!(code: billable_metric.code, properties: {ops_count: 4}, external_subscription_id: subscription_external_id)

      perform_usage_update
      expect(UsageMonitoring::TriggeredAlert.where(alert:).count).to eq(2)
      ta = alert.triggered_alerts.order(:created_at).last
      expect(ta.current_value).to eq(5500)
      expect(ta.crossed_thresholds.map(&:symbolize_keys)).to eq([
        {code: "alert", value: "4000.0", recurring: true},
        {code: "alert", value: "5000.0", recurring: true}
      ])
    end
  end

  context "when there is no alert" do
    it "does not track activity" do
      create_subscription({
        external_customer_id: customer.external_id,
        external_id: subscription_external_id,
        plan_code: plan.code
      })
      webhooks_sent = []
      subscription = customer.subscriptions.sole

      send_event!(code: billable_metric.code, properties: {ops_count: 20}, external_subscription_id: subscription_external_id)
      expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0

      perform_usage_update

      expect(webhooks_sent).to be_empty
    end
  end
end
