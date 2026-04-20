# frozen_string_literal: true

# NOTE: If hooli is not found, run 01_base.rb first
@organization = Organization.find_by!(name: "Hooli")
@customer = Customer.find_by!(external_id: "cust_john-doe")

def create_quote(organization:, customer:, **params)
  Quote.create!(
    organization: organization,
    customer: customer,
    **params
  )
end

# Create a chain of quotes
last_version = 3
(1..3).each do |version|
  quote = create_quote(
    organization: @organization,
    customer: @customer,
    sequential_id: 1,
    version: version,
    order_type: :subscription_creation,
    status: ((last_version == version) ? :draft : :voided),
    void_reason: ((last_version == version) ? nil : :manual),
    voided_at: ((last_version == version) ? nil : Time.current)
  )
  if last_version == version
    owners = User.where(email: ["gavin@hooli.com", "dinesh@hooli.com"])
    owners.each do |user|
      QuoteOwner.create!(
        quote: quote,
        user: user,
        organization: @organization
      )
    end
  end
end

# Add a draft quote per each customer
(1..5).each do |i|
  customer = Customer.find_by!(external_id: "cust_#{i}")
  create_quote(
    organization: @organization,
    customer: customer,
    order_type: :one_off
  )
end

def create_order_form(organization:, customer:, quote:, **params)
  OrderForm.create!(
    organization: organization,
    customer: customer,
    quote: quote,
    billing_snapshot: {items: []},
    **params
  )
end

# Chain of order forms on the flagship quote
flagship_quote = Quote.find_by!(
  organization: @organization,
  customer: @customer,
  sequential_id: 1,
  version: 3
)

create_order_form(
  organization: @organization,
  customer: @customer,
  quote: flagship_quote,
  status: :voided,
  voided_at: Time.current,
  void_reason: :manual
)

create_order_form(
  organization: @organization,
  customer: @customer,
  quote: flagship_quote,
  status: :expired,
  expires_at: 1.day.ago,
  voided_at: Time.current,
  void_reason: :expired
)

gavin = User.find_by!(email: "gavin@hooli.com")
create_order_form(
  organization: @organization,
  customer: @customer,
  quote: flagship_quote,
  status: :signed,
  signed_at: Time.current,
  signed_by_user_id: gavin.id
)

create_order_form(
  organization: @organization,
  customer: @customer,
  quote: flagship_quote,
  expires_at: 7.days.from_now
)

# A generated order form per sample customer
(1..5).each do |i|
  customer = Customer.find_by!(external_id: "cust_#{i}")
  quote = Quote.find_by!(
    organization: @organization,
    customer: customer,
    order_type: :one_off
  )
  create_order_form(
    organization: @organization,
    customer: customer,
    quote: quote
  )
end
