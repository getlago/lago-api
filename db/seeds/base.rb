# frozen_string_literal: true

require 'faker'
require 'factory_bot_rails'

# NOTE: create a user and an organization
user = User.create_with(password: 'ILoveLago')
  .find_or_create_by(email: 'gavin@hooli.com')

organization = Organization.find_or_create_by!(name: 'Hooli')
Membership.find_or_create_by!(user:, organization:, role: :admin)

# NOTE: define a billing model
sum_metric = BillableMetric.find_or_create_by!(
  organization:,
  aggregation_type: 'sum_agg',
  name: 'Sum BM',
  code: 'sum_bm',
  field_name: 'custom_field',
)

count_metric = BillableMetric.find_or_create_by!(
  organization:,
  aggregation_type: 'count_agg',
  name: 'Count BM',
  code: 'count_bm',
  field_name: 'customer_field',
)

plan = Plan.create_with(
  interval: 'monthly',
  pay_in_advance: false,
  amount_cents: 100,
  amount_currency: 'EUR',
).find_or_create_by!(
  organization:,
  name: 'Standard Plan',
  code: 'standard_plan',
)

Charge.create_with(
  charge_model: 'standard',
  amount_currency: 'EUR',
  properties: {
    amount: Faker::Number.between(from: 100, to: 500).to_s,
  },
).find_or_create_by!(
  plan:,
  billable_metric: sum_metric,
)

Charge.create_with(
  charge_model: 'standard',
  amount_currency: 'EUR',
  properties: {
    amount: Faker::Number.between(from: 100, to: 500).to_s,
  },
).find_or_create_by!(
  plan:,
  billable_metric: count_metric,
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
    currency: 'EUR',
  ).find_or_create_by!(
    organization:,
    external_id: "cust_#{i + 1}",
  )

  subscription_at = (Time.current - 6.months).beginning_of_month

  sub = Subscription.create_with(
    started_at: subscription_at,
    subscription_at:,
    status: :active,
    billing_time: :calendar,
  ).find_or_create_by!(
    customer:,
    external_id: SecureRandom.uuid,
    plan:,
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
        transaction_id: SecureRandom.uuid,
        timestamp: time - rand(0..12).seconds,
        created_at: time,
        code: sum_metric.code,
        properties: {
          custom_field: 10,
        },
        metadata: {
          user_agent: 'Lago Python v0.1.5',
          ip_address: Faker::Internet.ip_v4_address,
        },
      )
    end

    2.times do
      time = Time.current - offset.month - rand(1..20).days

      Event.create!(
        external_customer_id: customer.external_id,
        external_subscription_id: sub.external_id,
        organization_id: organization.id,
        transaction_id: SecureRandom.uuid,
        timestamp: time - rand(0..12).seconds,
        created_at: time,
        code: count_metric.code,
        metadata: {
          user_agent: 'Lago Python v0.1.5',
          ip_address: Faker::Internet.ip_v4_address,
        },
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
      transaction_id: SecureRandom.uuid,
      timestamp: time - 120.seconds,
      created_at: time,
      code: sum_metric.code,
      properties: {},
      metadata: {
        user_agent: 'Lago Python v0.1.5',
        ip_address: Faker::Internet.ip_v4_address,
      },
    )
  end

  # NOTE: Assigns events with invalid code
  5.times do
    time = Time.zone.now - rand(1..20).days

    Event.create!(
      external_customer_id: customer.external_id,
      external_subscription_id: sub.external_id,
      organization_id: organization.id,
      transaction_id: SecureRandom.uuid,
      timestamp: time - 120.seconds,
      created_at: time,
      code: 'foo',
      properties: {},
      metadata: {
        user_agent: 'Lago Python v0.1.5',
        ip_address: Faker::Internet.ip_v4_address,
      },
    )
  end
end

first_customer = organization.customers.first

wallet = Wallet.create!(
  customer: first_customer,
  name: 'My Active Wallet',
  status: :active,
  rate_amount: BigDecimal('1.00'),
  balance: BigDecimal('100.00'),
  ongoing_balance: BigDecimal('100.00'),
  ongoing_usage_balance: BigDecimal('100.00'),
  credits_balance: BigDecimal('100.00'),
  credits_ongoing_balance: BigDecimal('100.00'),
  credits_ongoing_usage_balance: BigDecimal('100.00'),
  currency: 'EUR',
)

Wallet.create!(
  customer: first_customer,
  name: 'My Terminated Wallet',
  status: :terminated,
  terminated_at: Time.zone.now - 3.days,
  rate_amount: BigDecimal('1.00'),
  balance: BigDecimal('86.00'),
  ongoing_balance: BigDecimal('86.00'),
  ongoing_usage_balance: BigDecimal('86.00'),
  credits_balance: BigDecimal('86.00'),
  credits_ongoing_balance: BigDecimal('86.00'),
  credits_ongoing_usage_balance: BigDecimal('86.00'),
  consumed_credits: BigDecimal('114.00'),
  currency: 'EUR',
)

3.times do
  WalletTransaction.create!(
    wallet:,
    transaction_type: :outbound,
    status: :settled,
    amount: BigDecimal('10.00'),
    credit_amount: BigDecimal('10.00'),
    settled_at: Time.zone.now,
    transaction_status: :purchased,
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
      transaction_id: SecureRandom.uuid,
      timestamp: time - rand(0..24).hours,
      created_at: time,
      code: sum_metric.code,
      properties: {
        custom_field: 10,
      },
      metadata: {
        user_agent: 'Lago Python v0.1.5',
        ip_address: Faker::Internet.ip_v4_address,
      },
    )
  end
end
