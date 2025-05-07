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
  customer = Customer.find_by(organization:, external_id: "cust_#{ext_id}")
  customer ||= FactoryBot.create(:customer, organization:, external_id: "cust_#{ext_id}")
  customer.subscriptions.create_with(
    started_at: Time.current,
    subscription_at: Time.current,
    status: :active,
    billing_time: :calendar
  ).find_or_create_by!(plan:, external_id: "sub_#{ext_id}")
end

sub = create_customer_with_sub("alerting-custom-alerts", plan:, organization:)
alert = UsageMonitoring::Alert.create_or_find_by!(alert_type: "usage_amount", organization:, subscription_external_id: sub.external_id, code: "default", name: "Default Alert")
alert.thresholds.delete_all
alert.thresholds.create!(value: 50_00, organization:)
alert.thresholds.create!(code: "warn", value: 80_00, organization:)
alert.thresholds.create!(code: "alert", value: 100_00, organization:)
alert.thresholds.create!(code: "panic", value: 33_00, organization:, recurring: true)

alert = UsageMonitoring::Alert.create_or_find_by!(alert_type: "usage_amount", organization:, billable_metric: ops_bm, subscription_external_id: sub.external_id, code: "default_bm", name: "BM Alert")
alert.thresholds.delete_all
alert.thresholds.create!(value: 30_00, organization:)
alert.thresholds.create!(code: "alert", value: 90_00, organization:)
