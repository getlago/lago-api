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
