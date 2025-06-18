# frozen_string_literal: true

organization ||= Organization.find_by(name: "Hooli")

Plan.create_with(
  interval: "monthly", pay_in_advance: false, amount_cents: 49_00, amount_currency: "EUR"
).find_or_create_by!(organization:, name: "Premium Plan", code: "premium_plan")

sub = Subscription.find_by(
  # organization:,
  external_id: "sub_entitlement_80554965"
)
if sub.nil?
  customer = Customer.create!(
    organization:,
    billing_entity: organization.billing_entities.first,
    external_id: "cust_#{SecureRandom.hex}",
    name: Faker::TvShows::SiliconValley.character,
    country: Faker::Address.country_code,
    email: Faker::Internet.email,
    currency: "EUR"
  )
  Subscription.create!(
    # organization:,
    external_id: "sub_entitlement_80554965",
    started_at: Time.current,
    subscription_at: Time.current,
    status: :active,
    billing_time: :calendar,
    plan:,
    customer:
  )
end

# SEATS
seats = Feature.create_with(
  name: "Number of seats",
  description: "Number of users of the account"
).find_or_create_by!(organization:, code: "seats")

# PrivilegeValue.where(privilege: seats.privileges).delete_all
seats.privileges.delete_all

max = seats.privileges.create!(organization:, code: "max", name: "Maximum", value_type: "integer")
max_admins = seats.privileges.create!(organization:, code: "max_admins", name: "Max Admins", value_type: "integer")

# PrivilegeValue.create!(organization:, privilege: min, plan:, value: 3) # Plan defaults
# PrivilegeValue.create!(organization:, privilege: max, plan:, value: 20) # Plan defaults
# PrivilegeValue.create!(organization:, privilege: max, subscription_external_id: sub.external_id, value: 99) # Subscription override

# Analytics API
analytics_api_feature = Feature.create_with(
  name: "Analytics API",
  description: "Access to all analytics data via REST API"
).find_or_create_by!(organization:, code: "analytics_api")

# PrivilegeValue.where(privilege: analytics_api_feature.privileges).delete_all
analytics_api_feature.privileges.delete_all

analytics = analytics_api_feature.privileges.create!(organization:, code: "enabled", value_type: "boolean")
# PrivilegeValue.create!(organization:, privilege: analytics, plan:, value: true)
# PrivilegeValue.create!(organization:, privilege: analytics, subscription_external_id: sub.external_id, value: false)

pp max_admins, max, analytics
