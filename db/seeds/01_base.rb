# frozen_string_literal: true

require "faker"
require "factory_bot_rails"

# NOTE: create a user and an organization
user = User.create_with(password: "ILoveLago")
  .find_or_create_by(email: "gavin@hooli.com")

organization = Organization.find_by(name: "Hooli")
if organization.nil?
  organization = Organization.create!(
    id: "11111111-2222-3333-4444-555555555555",
    name: "Hooli"
  )
end
organization.update!({
  premium_integrations: Organization::PREMIUM_INTEGRATIONS,
  invoice_footer: "Hooli is a fictional company."
})
BillingEntity.find_or_create_by!(organization:, name: "Hooli", code: "hooli")
Membership.find_or_create_by!(user:, organization:, role: :admin)
WebhookEndpoint.find_or_create_by!(organization:, webhook_url: "http://webhook/#{organization.id}")

organization.api_keys.destroy_all
organization.api_keys.create!(name: "Expired Key", expires_at: 1.day.ago, last_used_at: 36.hours.ago, permissions: {"customer" => ["read", "write"]})
k = organization.api_keys.create!(name: "Hooli Key", permissions: ApiKey.default_permissions)
k.update_columns(value: "lago_key-hooli-1234567890") # rubocop:disable Rails/SkipsModelValidations

# == BillableMetrics

sum_bm = BillableMetric.find_or_create_by!(
  organization:,
  aggregation_type: "sum_agg",
  name: "Sum BM",
  code: "sum_bm",
  field_name: "custom_field"
)

count_bm = BillableMetric.find_or_create_by!(
  organization:,
  aggregation_type: "count_agg",
  name: "Count BM",
  code: "count_bm",
  field_name: "customer_field"
)

# == Taxes

unless Tax.exists?(organization:, code: "lago_eu_fr_standard")
  Taxes::CreateService.call!(
    organization:,
    params: {
      name: "FR Standard",
      code: "lago_eu_fr_standard",
      description: "FR Standard",
      rate: 20
    }
  )
end

# == Addons

unless AddOn.exists?(organization:, code: "setup_fee")
  AddOns::CreateService.call!(
    organization_id: organization.id,
    name: "Setup Fee",
    code: "setup_fee",
    description: "Fee for setting up the subscription",
    amount_cents: 100_00,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"]
  )
end

unless AddOn.exists?(organization:, code: "setup_fee")
  AddOns::CreateService.call!(
    organization_id: organization.id,
    name: "Hour of Premium Support",
    code: "support_hour",
    description: "One hour of support from our experts",
    amount_cents: 84_99,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"]
  )
end

# == Coupons

unless Coupon.exists?(organization:, code: "20_percent_off")
  Coupons::CreateService.call!(
    organization_id: organization.id,
    name: "20% off",
    code: "20_percent_off",
    coupon_type: "percentage",
    percentage_rate: 20,
    frequency: "forever",
    expiration: "no_expiration"
  )
end

unless Coupon.exists?(organization:, code: "10_euro_off")
  Coupons::CreateService.call!(
    organization_id: organization.id,
    name: "10€ off",
    code: "10_euro_off",
    coupon_type: "fixed_amount",
    amount_cents: 1000,
    amount_currency: "EUR",
    frequency: "forever",
    expiration: "no_expiration"
  )
end

# == Plans

unless Plan.exists?(organization:, code: "standard_plan")
  Plans::CreateService.call!(
    organization_id: organization.id,
    name: "Standard Plan",
    code: "standard_plan",
    interval: "monthly",
    pay_in_advance: true,
    amount_cents: 19_99,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"],
    charges: [
      {
        billable_metric_id: sum_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 100.to_s
        }
      },
      {
        billable_metric_id: count_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 499.to_s
        }
      }
    ]
  )
end

unless Plan.exists?(organization:, code: "premium_plan")
  Plans::CreateService.call!(
    organization_id: organization.id,
    name: "Premium Plan",
    code: "premium_plan",
    interval: "monthly",
    pay_in_advance: true,
    amount_cents: 100_00,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"],
    charges: [
      {
        billable_metric_id: sum_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 30.to_s
        }
      },
      {
        billable_metric_id: count_bm.id,
        charge_model: "standard",
        amount_currency: "EUR",
        pay_in_advance: false,
        properties: {
          amount: 399.to_s
        }
      }
    ]
  )
end
