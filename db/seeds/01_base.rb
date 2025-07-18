# frozen_string_literal: true

require "faker"
require "factory_bot_rails"

# NOTE: create a user and an organization
user = User.create_with(password: "ILoveLago")
  .find_or_create_by(email: "gavin@hooli.com")

organization = Organization.find_or_create_by!(name: "Hooli")
organization.premium_integrations = Organization::PREMIUM_INTEGRATIONS
organization.save!
billing_entity = BillingEntity.find_or_create_by!(organization: organization, name: "Hooli", code: "hooli")
ApiKey.find_or_create_by!(organization:)
Membership.find_or_create_by!(user:, organization:, role: :admin)

# NOTE: define a billing model
sum_metric = BillableMetric.find_or_create_by!(
  organization:,
  aggregation_type: "sum_agg",
  name: "Sum BM",
  code: "sum_bm",
  field_name: "custom_field"
)

count_metric = BillableMetric.find_or_create_by!(
  organization:,
  aggregation_type: "count_agg",
  name: "Count BM",
  code: "count_bm",
  field_name: "customer_field"
)

plan = Plan.create_with(
  interval: "monthly",
  pay_in_advance: false,
  amount_cents: 100,
  amount_currency: "EUR"
).find_or_create_by!(
  organization:,
  name: "Standard Plan",
  code: "standard_plan"
)

# Tax
if !Tax.exists?(organization:, code: "lago_eu_fr_standard")
  Taxes::CreateService.call!(
    organization:,
    params: {
      name: "Lago EU FR Standard",
      code: "lago_eu_fr_standard",
      description: "Lago EU FR Standard",
      rate: 20
    }
  )
end

# Pay-in-advance plan
if !Plan.exists?(organization:, code: "pay_in_advance_plan")
  Plans::CreateService.call!(
    organization_id: organization.id,
    name: "Pay-in-advance Plan",
    code: "pay_in_advance_plan",
    interval: "monthly",
    pay_in_advance: true,
    amount_cents: 10000,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"]
  )
end

# Add-on
if !AddOn.exists?(organization:, code: "setup_fee")
  AddOns::CreateService.call!(
    organization_id: organization.id,
    name: "Setup Fee",
    code: "setup_fee",
    description: "Fee for setting up the subscription",
    amount_cents: 10000,
    amount_currency: "EUR",
    tax_codes: ["lago_eu_fr_standard"]
  )
end

Charge.create_with(
  organization:,
  charge_model: "standard",
  amount_currency: "EUR",
  properties: {
    amount: Faker::Number.between(from: 100, to: 500).to_s
  }
).find_or_create_by!(
  plan:,
  billable_metric: sum_metric
)

Charge.create_with(
  organization:,
  charge_model: "standard",
  amount_currency: "EUR",
  properties: {
    amount: Faker::Number.between(from: 100, to: 500).to_s
  }
).find_or_create_by!(
  plan:,
  billable_metric: count_metric
)

# NOTE: define customers
5.times do |i|
  customer = Customer.create_with(
    name: Faker::TvShows::SiliconValley.character,
    country: Faker::Address.country_code,
    address_line1: Faker::Address.street_address,
    address_line2: Faker::Address.secondary_address,
    state: Faker::Address.state,
    zipcode: Faker::Address.zip_code,
    email: Faker::Internet.email,
    city: Faker::Address.city,
    url: Faker::Internet.url,
    phone: Faker::PhoneNumber.phone_number,
    logo_url: Faker::Internet.url,
    legal_name: Faker::Company.name,
    legal_number: Faker::Company.duns_number,
    currency: "EUR"
  ).find_or_create_by!(
    organization:,
    billing_entity:,
    external_id: "cust_#{i + 1}"
  )

  subscription_at = (Time.current - 6.months).beginning_of_month

  sub = Subscription.create_with(
    organization:,
    started_at: subscription_at,
    subscription_at:,
    status: :active,
    billing_time: :calendar
  ).find_or_create_by!(
    customer:,
    external_id: "cust_#{SecureRandom.hex}",
    plan:
  )

  next if Event.where(customer_id: customer.id).exists?

  # NOTE: Assigns valid events
  6.times do |offset|
    5.times do
      time = Time.current - offset.month - rand(1..20).days

      Event.create!(
        external_customer_id: customer.external_id,
        external_subscription_id: sub.external_id,
        organization_id: organization.id,
        transaction_id: "tr-#{SecureRandom.hex}",
        timestamp: time - rand(0..12).seconds,
        created_at: time,
        code: sum_metric.code,
        properties: {
          custom_field: 10
        },
        metadata: {
          user_agent: "Lago Python v0.1.5",
          ip_address: Faker::Internet.ip_v4_address
        }
      )
    end

    2.times do
      time = Time.current - offset.month - rand(1..20).days

      Event.create!(
        external_customer_id: customer.external_id,
        external_subscription_id: sub.external_id,
        organization_id: organization.id,
        transaction_id: "tr-#{SecureRandom.hex}",
        timestamp: time - rand(0..12).seconds,
        created_at: time,
        code: count_metric.code,
        metadata: {
          user_agent: "Lago Python v0.1.5",
          ip_address: Faker::Internet.ip_v4_address
        }
      )
    end
  end

  # NOTE: Assigns events missing custom property
  5.times do
    time = Time.zone.now - rand(1..20).days

    Event.create!(
      external_customer_id: customer.external_id,
      external_subscription_id: sub.external_id,
      organization_id: organization.id,
      transaction_id: "tr-#{SecureRandom.hex}",
      timestamp: time - 120.seconds,
      created_at: time,
      code: sum_metric.code,
      properties: {},
      metadata: {
        user_agent: "Lago Python v0.1.5",
        ip_address: Faker::Internet.ip_v4_address
      }
    )
  end

  # NOTE: Assigns events with invalid code
  5.times do
    time = Time.zone.now - rand(1..20).days

    Event.create!(
      external_customer_id: customer.external_id,
      external_subscription_id: sub.external_id,
      organization_id: organization.id,
      transaction_id: "tr-#{SecureRandom.hex}",
      timestamp: time - 120.seconds,
      created_at: time,
      code: "foo",
      properties: {},
      metadata: {
        user_agent: "Lago Python v0.1.5",
        ip_address: Faker::Internet.ip_v4_address
      }
    )
  end
end

first_customer = organization.customers.first

wallet = Wallet.create!(
  organization_id: organization.id,
  customer: first_customer,
  name: "My Active Wallet",
  status: :active,
  rate_amount: BigDecimal("1.00"),
  balance: BigDecimal("100.00"),
  ongoing_balance: BigDecimal("100.00"),
  ongoing_usage_balance: BigDecimal("100.00"),
  credits_balance: BigDecimal("100.00"),
  credits_ongoing_balance: BigDecimal("100.00"),
  credits_ongoing_usage_balance: BigDecimal("100.00"),
  currency: "EUR"
)

Wallet.create!(
  organization_id: organization.id,
  customer: first_customer,
  name: "My Terminated Wallet",
  status: :terminated,
  terminated_at: Time.zone.now - 3.days,
  rate_amount: BigDecimal("1.00"),
  balance: BigDecimal("86.00"),
  ongoing_balance: BigDecimal("86.00"),
  ongoing_usage_balance: BigDecimal("86.00"),
  credits_balance: BigDecimal("86.00"),
  credits_ongoing_balance: BigDecimal("86.00"),
  credits_ongoing_usage_balance: BigDecimal("86.00"),
  consumed_credits: BigDecimal("114.00"),
  currency: "EUR"
)

3.times do
  WalletTransaction.create!(
    organization_id: organization.id,
    wallet:,
    transaction_type: :outbound,
    status: :settled,
    amount: BigDecimal("10.00"),
    credit_amount: BigDecimal("10.00"),
    settled_at: Time.zone.now,
    transaction_status: :invoiced
  )
end

# NOTE: Regenerate events for the customers
organization.customers.find_each do |customer|
  5.times do
    time = Time.zone.now

    Event.create!(
      external_customer_id: customer.external_id,
      external_subscription_id: customer.active_subscriptions&.first&.external_id,
      organization_id: organization.id,
      transaction_id: "tr-#{SecureRandom.hex}",
      timestamp: time - rand(0..24).hours,
      created_at: time,
      code: sum_metric.code,
      properties: {
        custom_field: 10
      },
      metadata: {
        user_agent: "Lago Python v0.1.5",
        ip_address: Faker::Internet.ip_v4_address
      }
    )
  end
end
