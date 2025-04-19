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

  let(:alert) do
    alert = UsageMonitoring::UsageAmountAlert.create!(organization:, subscription_external_id:, code: :simple)
    alert.thresholds.create!(value: 15_00, code: :warn, organization:)
    alert.thresholds.create!(value: 30_00, code: :warn, organization:)
    alert.thresholds.create!(value: 50_00, code: :alert, organization:)
    alert.thresholds.create!(value: 1230_00, code: :block, organization:)
    alert.reload
  end

  let(:alert_on_charge) do
    alert = UsageMonitoring::ChargeUsageAmountAlert.create!(organization:, subscription_external_id:, code: :metric, charge: charge_2)
    alert.thresholds.create!(value: 399_00, code: :warn, organization:)
    alert.thresholds.create!(value: 1000_00, code: :alert, organization:)
    alert.reload
  end

  include_context "with webhook tracking"

  def send_event!(params)
    create_event({
      transaction_id: "tr_#{SecureRandom.hex(16)}",
      external_subscription_id: subscription_external_id
    }.merge(params))
  end

  before do
    charge
    charge_2
  end

  it "works" do
    create_subscription({
      external_customer_id: customer.external_id,
      external_id: subscription_external_id,
      plan_code: plan.code
    })
    subscription = customer.subscriptions.sole
    alert
    alert_on_charge

    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0
    send_event!(code: billable_metric.code, properties: {ops_count: 2})
    # SubscriptionActivity is created by PostProcessEvents
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 1

    perform_subscription_activities

    expect(UsageMonitoring::TriggeredAlert.where(alert:).count).to eq(0)

    send_event!(code: billable_metric.code, properties: {ops_count: 2})
    send_event!(code: billable_metric.code, properties: {ops_count: 2})

    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 1
    perform_subscription_activities
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0

    ta = alert.triggered_alerts.sole
    expect(ta.current_value).to eq(3000)
    expect(ta.previous_value).to eq(1000)
    expect(ta.crossed_thresholds.map(&:symbolize_keys)).to eq([
      {code: "warn", value: "1500.0"},
      {code: "warn", value: "3000.0"}
    ])

    # WITH EVENTS ON CHARGE WITH SPECIAL ALERT
    # max value: 9,223,372,036,854,775,807
    send_event!(code: bm_2.code, properties: {api_count: 4})
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 1
    perform_subscription_activities
    expect(UsageMonitoring::SubscriptionActivity.where(subscription:).count).to eq 0

    expect(alert.triggered_alerts.count).to eq 2
    expect(alert_on_charge.triggered_alerts.count).to eq 1
  end

  context "with deleted_at" do
    it "maybe works" do
      alert = UsageMonitoring::UsageAmountAlert.create!(organization:, subscription_external_id:)
      expect(alert.deleted_at).to be_nil
      alert.discard!
      expect(alert.deleted_at).not_to be_nil
      alert.reload
      expect(alert.deleted_at).not_to be_nil
    end
  end
end
