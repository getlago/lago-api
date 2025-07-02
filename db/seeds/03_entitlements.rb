# frozen_string_literal: true

# Created in 01_base.rb
organization ||= Organization.find_by!(name: "Hooli")
plan = Plan.find_by!(code: "standard_plan")

sub = Subscription.find_by(external_id: "sub_entitlement_80554965")
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
    organization:,
    external_id: "sub_entitlement_80554965",
    started_at: Time.current,
    subscription_at: Time.current,
    status: :active,
    billing_time: :calendar,
    plan:,
    customer:
  )
end

# SEATS - feature with privilege and subscription overrides
seats = Entitlement::Feature.create_with(
  name: "Number of seats",
  description: "Number of users of the account"
).find_or_create_by!(organization:, code: "seats")

Entitlement::EntitlementValue.where(organization:, privilege: seats.privileges).delete_all
Entitlement::Entitlement.where(organization:, feature: seats).delete_all
seats.privileges.delete_all

max = seats.privileges.create!(organization:, code: "max", name: "Maximum", value_type: "integer")
max_admins = seats.privileges.create!(organization:, code: "max_admins", name: "Max Admins", value_type: "integer")
root = seats.privileges.create!(organization:, code: "root", name: "Allow root user", value_type: "boolean")

fe = Entitlement::Entitlement.create!(organization:, feature: seats, plan:)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max, value: 20)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max_admins, value: 3)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: root, value: true)
# fe_sub = FeatureEntitlement.create!(organization:, feature: seats, subscription_external_id: sub.external_id)
# FeatureEntitlementValue.create!(organization:, privilege: max, entitlement: fe_sub, value: 99) # Subscription override

# Feature in the plan, without any privilege
analytics_api_feature = Entitlement::Feature.create_with(
  name: "Analytics API",
  description: "Access to all analytics data via REST API"
).find_or_create_by!(organization:, code: "analytics_api")
analytics_api_feature.privileges.delete_all

Entitlement::Entitlement.where(organization:, feature: analytics_api_feature, plan:).delete_all
Entitlement::Entitlement.create!(organization:, feature: analytics_api_feature, plan:)

# Feature not in the plan but added to the subscription
salesforce = Entitlement::Feature.create_with(
  name: "Salesforce Integration"
).find_or_create_by!(organization:, code: "salesforce")
salesforce.privileges.delete_all

# Entitlement::Entitlement.where(organization:, feature: salesforce).delete_all
# Entitlement::Entitlement.create!(organization:, feature: salesforce, subscription_external_id: sub.external_id)

# Feature attached to the plan but removed from the subscription
_support = Entitlement::Feature.create_with(
  name: "Premium Support"
).find_or_create_by!(organization:, code: "premium_support")

# FeatureEntitlement.where(organization:, feature: support, plan:).delete_all
# FeatureEntitlement.create!(organization:, feature: support, plan:)
# SubscriptionFeatureEntitlementRemoval.where(organization:, feature: support).delete_all
# SubscriptionFeatureEntitlementRemoval.create!(organization:, feature: support, subscription_external_id: sub.external_id)

# Feature with Select
sso = Entitlement::Feature.create_with(
  name: "SSO"
).find_or_create_by!(organization:, code: "sso")
sso.privileges.delete_all

provider = sso.privileges.create!(organization:,
  code: "provider",
  name: "Provider Name",
  value_type: "select",
  config: {select_options: %w[okta ad google custom]})

Entitlement::Entitlement.where(organization:, feature: sso, plan:).delete_all
fe = Entitlement::Entitlement.create!(organization:, feature: sso, plan:)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: provider, value: "okta")
