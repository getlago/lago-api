# frozen_string_literal: true

organization ||= Organization.find_by(name: "Hooli")

plan = Plan.create_with(
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

FeatureEntitlementValue.where(privilege: seats.privileges).delete_all
seats.privileges.delete_all

max = seats.privileges.create!(organization:, code: "max", name: "Maximum", value_type: "integer")
max_admins = seats.privileges.create!(organization:, code: "max_admins", name: "Max Admins", value_type: "integer")

FeatureEntitlement.where(organization:, feature: seats, plan:).delete_all
fe = FeatureEntitlement.create!(organization:, feature: seats, plan:)
FeatureEntitlementValue.create!(organization:, feature_entitlement: fe, privilege: max, value: 20) # Plan defaults
FeatureEntitlementValue.create!(organization:, feature_entitlement: fe, privilege: max_admins, value: 3) # Plan defaults
fe_sub = FeatureEntitlement.create!(organization:, feature: seats, subscription_external_id: sub.external_id)
FeatureEntitlementValue.create!(organization:, privilege: max, feature_entitlement: fe_sub, value: 99) # Subscription override

# Analytics API
analytics_api_feature = Feature.create_with(
  name: "Analytics API",
  description: "Access to all analytics data via REST API"
).find_or_create_by!(organization:, code: "analytics_api")

analytics_api_feature.privileges.delete_all

FeatureEntitlement.where(organization:, feature: analytics_api_feature, plan:).delete_all
FeatureEntitlement.create!(organization:, feature: analytics_api_feature, plan:)

# Salesforce
salesforce = Feature.create_with(
  name: "Salesforce Integration"
).find_or_create_by!(organization:, code: "salesforce")

salesforce.privileges.delete_all

FeatureEntitlement.where(organization:, feature: salesforce).delete_all
FeatureEntitlement.create!(organization:, feature: salesforce, subscription_external_id: sub.external_id)

pp max_admins, max, salesforce

# Premium Support
support = Feature.create_with(
  name: "Premium Support"
).find_or_create_by!(organization:, code: "premium_support")

FeatureEntitlement.where(organization:, feature: support, plan:).delete_all
FeatureEntitlement.create!(organization:, feature: support, plan:)
SubscriptionFeatureRemoval.create!(organization:, feature: support, subscription_external_id: sub.external_id)
