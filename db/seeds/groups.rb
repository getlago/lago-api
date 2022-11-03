# frozen_string_literal: true

organization = Organization.find_or_create_by!(name: 'Hooli')

plan = Plan.create_with(
  interval: 'monthly',
  pay_in_advance: false,
  amount_cents: 100,
  amount_currency: 'EUR',
).find_or_create_by!(
  organization: organization,
  name: 'Group Plan',
  code: 'group_plan',
)

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
  organization: organization,
  external_id: 'cust_with_dimensions',
)

subscription = Subscription.create_with(
  started_at: Time.current - 3.months,
  subscription_date: (Time.current - 3.months).to_date,
  status: :active,
).find_or_create_by!(
  customer: customer,
  external_id: SecureRandom.uuid,
  plan: plan,
)

# NOTE: billable metric with one dimension group
one_dimension_metric = BillableMetric.find_or_create_by!(
  organization: organization,
  aggregation_type: 'count_agg',
  name: 'Count BM - One dimension',
  code: 'count_bm_one_dimension',
)

france = Group.find_or_create_by!(
  billable_metric: one_dimension_metric,
  key: 'country',
  value: 'france',
)

italy = Group.find_or_create_by!(
  billable_metric: one_dimension_metric,
  key: 'country',
  value: 'italy',
)

Charge.create_with(
  charge_model: 'standard',
  amount_currency: 'EUR',
  group_properties: [
    GroupProperty.new(group: france, values: { amount: Faker::Number.between(from: 100, to: 500).to_s }),
    GroupProperty.new(group: italy, values: { amount: Faker::Number.between(from: 100, to: 500).to_s }),
  ],
).find_or_create_by!(
  plan: plan,
  billable_metric: one_dimension_metric,
)

unless customer.events.exists?
  time = Time.current
  2.times do
    Event.create!(
      customer: customer,
      subscription: subscription,
      organization: organization,
      transaction_id: SecureRandom.uuid,
      timestamp: time - rand(0..12).seconds,
      created_at: time,
      code: one_dimension_metric.code,
      properties: { country: 'france' },
      metadata: {
        user_agent: 'Lago Python v0.1.5',
        ip_address: Faker::Internet.ip_v4_address,
      },
    )
  end

  Event.create!(
    customer: customer,
    subscription: subscription,
    organization: organization,
    transaction_id: SecureRandom.uuid,
    timestamp: time - rand(0..12).seconds,
    created_at: time,
    code: one_dimension_metric.code,
    properties: { country: 'italy' },
    metadata: {
      user_agent: 'Lago Python v0.1.5',
      ip_address: Faker::Internet.ip_v4_address,
    },
  )
end

# NOTE: billable metric with two dimensions group
two_dimensions_metric = BillableMetric.find_or_create_by!(
  organization: organization,
  aggregation_type: 'count_agg',
  name: 'Count BM - Two dimensions',
  code: 'count_bm_two_dimensions',
)

aws = Group.find_or_create_by!(
  billable_metric: two_dimensions_metric,
  key: 'cloud',
  value: 'AWS',
)
aws_usa = Group.find_or_create_by!(
  billable_metric: two_dimensions_metric,
  key: 'region',
  value: 'usa',
  parent_group_id: aws.id,
)
aws_europe = Group.find_or_create_by!(
  billable_metric: two_dimensions_metric,
  key: 'region',
  value: 'europe',
  parent_group_id: aws.id,
)
google = Group.find_or_create_by!(
  billable_metric: two_dimensions_metric,
  key: 'cloud',
  value: 'Google',
)
google_usa = Group.find_or_create_by!(
  billable_metric: two_dimensions_metric,
  key: 'region',
  value: 'usa',
  parent_group_id: google.id,
)

Charge.create_with(
  charge_model: 'standard',
  amount_currency: 'EUR',
  group_properties: [
    GroupProperty.new(group: aws_usa, values: { amount: Faker::Number.between(from: 100, to: 500).to_s }),
    GroupProperty.new(group: aws_europe, values: { amount: Faker::Number.between(from: 100, to: 500).to_s }),
    GroupProperty.new(group: google_usa, values: { amount: Faker::Number.between(from: 100, to: 500).to_s }),
  ],
).find_or_create_by!(
  plan: plan,
  billable_metric: two_dimensions_metric,
)

2.times do
  Event.create!(
    customer: customer,
    subscription: subscription,
    organization: organization,
    transaction_id: SecureRandom.uuid,
    timestamp: time - rand(0..12).seconds,
    created_at: time,
    code: two_dimensions_metric.code,
    properties: {
      cloud: 'AWS',
      region: 'france',
    },
    metadata: {
      user_agent: 'Lago Python v0.1.5',
      ip_address: Faker::Internet.ip_v4_address,
    },
  )
end

Event.create!(
  customer: customer,
  subscription: subscription,
  organization: organization,
  transaction_id: SecureRandom.uuid,
  timestamp: time - rand(0..12).seconds,
  created_at: time,
  code: two_dimensions_metric.code,
  properties: {
    cloud: 'AWS',
    region: 'europe',
  },
  metadata: {
    user_agent: 'Lago Python v0.1.5',
    ip_address: Faker::Internet.ip_v4_address,
  },
)

Event.create!(
  customer: customer,
  subscription: subscription,
  organization: organization,
  transaction_id: SecureRandom.uuid,
  timestamp: time - rand(0..12).seconds,
  created_at: time,
  code: two_dimensions_metric.code,
  properties: {
    cloud: 'Google',
    region: 'usa',
  },
  metadata: {
    user_agent: 'Lago Python v0.1.5',
    ip_address: Faker::Internet.ip_v4_address,
  },
)

Event.create!(
  customer: customer,
  subscription: subscription,
  organization: organization,
  transaction_id: SecureRandom.uuid,
  timestamp: time - rand(0..12).seconds,
  created_at: time,
  code: two_dimensions_metric.code,
  properties: {
    cloud: 'Google',
    region: 'france',
  },
  metadata: {
    user_agent: 'Lago Python v0.1.5',
    ip_address: Faker::Internet.ip_v4_address,
  },
)
