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
  sub = Subscription.create!(
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

Entitlement::EntitlementValue.where(organization:, privilege: seats.privileges.with_discarded).with_discarded.delete_all
Entitlement::Entitlement.where(organization:, feature: seats).with_discarded.delete_all
seats.privileges.with_discarded.delete_all

max = seats.privileges.create!(organization:, code: "max", name: "Maximum", value_type: "integer")
max_admins = seats.privileges.create!(organization:, code: "max_admins", name: "Max Admins", value_type: "integer")
root = seats.privileges.create!(organization:, code: "root", name: "Allow root user", value_type: "boolean")

fe = Entitlement::Entitlement.create!(organization:, feature: seats, plan:)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max, value: 20)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max_admins, value: 3_000, deleted_at: Time.current)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max_admins, value: 3)
fe_sub = Entitlement::Entitlement.create!(organization:, feature: seats, subscription_id: sub.id)
# Subscription override for max, root does not exist in the plan
Entitlement::EntitlementValue.create!(organization:, entitlement: fe_sub, privilege: max, value: 99)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe_sub, privilege: root, value: true)

# Feature in the plan, without any privilege
analytics_api_feature = Entitlement::Feature.create_with(
  name: "Analytics API",
  description: "Access to all analytics data via REST API"
).find_or_create_by!(organization:, code: "analytics_api")
analytics_api_feature.privileges.with_discarded.delete_all

Entitlement::Entitlement.where(organization:, feature: analytics_api_feature, plan:).with_discarded.delete_all
Entitlement::Entitlement.create!(organization:, feature: analytics_api_feature, plan:)

# Feature was in the plan but deleted, and in subscription but deleted
acls = Entitlement::Feature.create_with(
  name: "Granular permissions"
).find_or_create_by!(organization:, code: "acls")
acls.privileges.with_discarded.delete_all

Entitlement::Entitlement.where(organization:, feature: acls).with_discarded.delete_all
Entitlement::Entitlement.create!(organization:, feature: acls, plan:, deleted_at: Time.current)
# Entitlement::Entitlement.create!(organization:, feature: acls, subscription: sub, deleted_at: Time.current)

# Feature not in the plan but added to the subscription
salesforce = Entitlement::Feature.create_with(
  name: "Salesforce Integration"
).find_or_create_by!(organization:, code: "salesforce")
salesforce.privileges.with_discarded.delete_all

Entitlement::Entitlement.where(organization:, feature: salesforce).with_discarded.delete_all
Entitlement::Entitlement.create!(organization:, feature: salesforce, subscription_id: sub.id)

# Feature attached to the plan but removed from the subscription
support = Entitlement::Feature.create_with(
  name: "Premium Support"
).find_or_create_by!(organization:, code: "premium_support")
Entitlement::SubscriptionFeatureRemoval.where(feature: support).with_discarded.delete_all
Entitlement::Entitlement.where(organization:, feature: support).with_discarded.delete_all
Entitlement::Entitlement.create!(organization:, feature: support, plan:)
Entitlement::Entitlement.create!(organization:, feature: support, subscription_id: sub.id)
Entitlement::SubscriptionFeatureRemoval.create!(organization:, feature: support, subscription_id: sub.id)

# Feature with Select
sso = Entitlement::Feature.create_with(
  name: "SSO"
).find_or_create_by!(organization:, code: "sso")
Entitlement::SubscriptionFeatureRemoval.where(feature: sso).with_discarded.delete_all
Entitlement::EntitlementValue.where(organization:, privilege: sso.privileges).with_discarded.delete_all
sso.privileges.with_discarded.delete_all

provider = sso.privileges.create!(organization:,
  code: "provider",
  name: "Provider Name",
  value_type: "select",
  config: {select_options: %w[okta ad google custom]})

Entitlement::Entitlement.where(organization:, feature: sso, plan:).with_discarded.delete_all
fe = Entitlement::Entitlement.create!(organization:, feature: sso, plan:)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: provider, value: "okta")
Entitlement::SubscriptionFeatureRemoval.create!(organization:, feature: sso, deleted_at: Time.current, subscription_id: sub.id)
