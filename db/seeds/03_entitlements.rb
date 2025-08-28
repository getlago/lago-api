# frozen_string_literal: true

def clean_up_feature!(feature)
  Entitlement::SubscriptionFeatureRemoval.where(feature: feature).with_discarded.delete_all
  Entitlement::SubscriptionFeatureRemoval.where(privilege: feature.privileges.with_discarded).with_discarded.delete_all
  Entitlement::EntitlementValue.where(privilege: feature.privileges.with_discarded).with_discarded.delete_all
  Entitlement::Entitlement.where(feature: feature).with_discarded.delete_all
  feature.privileges.with_discarded.delete_all
end

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

  unless Subscription.where(external_id: "sub_entitlement_NO_OVERRIDE", customer:).exists?
    Subscription.create!(
      organization:,
      external_id: "sub_entitlement_NO_OVERRIDE",
      started_at: Time.current,
      subscription_at: Time.current,
      status: :active,
      billing_time: :calendar,
      plan:,
      customer:
    )
  end
end

# == seats - feature with privilege and subscription overrides
seats = Entitlement::Feature.create_with(
  name: "Number of seats",
  description: "Number of users of the account"
).find_or_create_by!(organization:, code: "seats")

clean_up_feature!(seats)

max = seats.privileges.create!(organization:, code: "max", name: "Maximum", value_type: "integer", created_at: 20.minutes.ago)
max_admins = seats.privileges.create!(organization:, code: "max_admins", name: "Max Admins", value_type: "integer", created_at: 10.minutes.ago)
root = seats.privileges.create!(organization:, code: "root", name: "Allow root user", value_type: "boolean", created_at: 15.minutes.ago)

fe = Entitlement::Entitlement.create!(organization:, feature: seats, plan:, created_at: 1.hour.ago)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max, value: 20)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max_admins, value: 3_000, deleted_at: Time.current)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: max_admins, value: 3, created_at: 8.minutes.ago)
fe_sub = Entitlement::Entitlement.create!(organization:, feature: seats, subscription_id: sub.id)

# Subscription override for max, root does not exist in the plan
Entitlement::EntitlementValue.create!(organization:, entitlement: fe_sub, privilege: max, value: 99)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe_sub, privilege: root, value: true)

# == analytics_api - Feature in the plan, without any privilege
analytics_api_feature = Entitlement::Feature.create_with(
  name: "Analytics API",
  description: "Access to all analytics data via REST API"
).find_or_create_by!(organization:, code: "analytics_api")

clean_up_feature!(analytics_api_feature)

Entitlement::Entitlement.create!(organization:, feature: analytics_api_feature, plan:, created_at: 1.year.ago)

# == acls - Feature was in the plan but deleted, and in subscription but deleted
acls = Entitlement::Feature.create_with(
  name: "Granular permissions"
).find_or_create_by!(organization:, code: "acls")

clean_up_feature!(acls)

Entitlement::Entitlement.create!(organization:, feature: acls, plan:, deleted_at: Time.current)
# Entitlement::Entitlement.create!(organization:, feature: acls, subscription: sub, deleted_at: Time.current)

# == salesforce - Feature not in the plan but added to the subscription
salesforce = Entitlement::Feature.create_with(
  name: "Salesforce Integration"
).find_or_create_by!(organization:, code: "salesforce")

clean_up_feature!(salesforce)

Entitlement::Entitlement.create!(organization:, feature: salesforce, subscription_id: sub.id)

# == support - Feature attached to the plan but removed from the subscription
support = Entitlement::Feature.create_with(
  name: "Premium Support"
).find_or_create_by!(organization:, code: "premium_support")

clean_up_feature!(support)

Entitlement::Entitlement.create!(organization:, feature: support, plan:)
Entitlement::Entitlement.create!(organization:, feature: support, subscription_id: sub.id)
Entitlement::SubscriptionFeatureRemoval.create!(organization:, feature: support, subscription_id: sub.id)

# == sso - Feature with Select and ALL PRIVILEGE OVERRIDDEN ("empty line" added)
sso = Entitlement::Feature.create_with(
  name: "SSO"
).find_or_create_by!(organization:, code: "sso")

clean_up_feature!(sso)

provider = sso.privileges.create!(organization:,
  code: "provider",
  name: "Provider Name",
  value_type: "select",
  config: {select_options: %w[okta ad google custom]})

fe = Entitlement::Entitlement.create!(organization:, feature: sso, plan:, created_at: 10.days.ago)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe, privilege: provider, value: "okta")

fe_sub = Entitlement::Entitlement.create!(organization:, feature: sso, subscription: sub, created_at: 1.day.ago)
Entitlement::EntitlementValue.create!(organization:, entitlement: fe_sub, privilege: provider, value: "google")

Entitlement::SubscriptionFeatureRemoval.create!(organization:, feature: sso, deleted_at: Time.current, subscription_id: sub.id)
