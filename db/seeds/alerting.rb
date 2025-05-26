# frozen_string_literal: true

organization ||= Organization.find_by(name: "Hooli")

# Create Plan with default alerts
# The pay in advance charge helps us test alerting by sending events
plan = Plan.create_with(
  interval: "monthly", pay_in_advance: false, amount_cents: 49_00, amount_currency: "EUR"
).find_or_create_by!(organization:, name: "Premium Plan", code: "premium_plan")

ops_bm = BillableMetric.find_or_create_by!(
  organization:,
  aggregation_type: "sum_agg",
  name: "Operations",
  code: "ops",
  field_name: "ops_count"
)

Charge.create_with(charge_model: "standard", amount_currency: "EUR", properties: {
  amount: "500"
}).find_or_create_by!(plan:, billable_metric: ops_bm)

def create_customer_with_sub(ext_id, plan:, organization:)
  customer = FactoryBot.create(:customer, organization:, external_id: "cust_#{ext_id}")
  customer.subscriptions.create!(
    started_at: Time.current,
    subscription_at: Time.current,
    status: :active,
    billing_time: :calendar,
    plan:,
    external_id: "sub_#{ext_id}"
  )
end

sub = create_customer_with_sub("alerting-#{SecureRandom.hex}", plan:, organization:)

UsageMonitoring::CreateAlertService.call(organization:, subscription: sub, params: {
  alert_type: "usage_amount",
  code: "default",
  name: "Default Alert",
  thresholds: [
    {code: "warn", value: 80_00},
    {code: "alert", value: 100_00},
    {code: "panic", value: 33_00, recurring: true}
  ]
})

UsageMonitoring::CreateAlertService.call(organization:, subscription: sub, params: {
  alert_type: "lifetime_usage_amount",
  code: "total",
  thresholds: [
    {code: "info", value: 1000_00}
  ]
})

UsageMonitoring::CreateAlertService.call(organization:, subscription: sub, params: {
  alert_type: "billable_metric_usage_amount",
  billable_metric: ops_bm,
  code: "ops",
  name: "Operations Alert",
  thresholds: [
    {value: 50_00},
    {value: 10_00, recurring: true}
  ]
})
