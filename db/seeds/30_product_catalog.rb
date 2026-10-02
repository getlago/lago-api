# frozen_string_literal: true

# The product catalog is the v2 billing surface. Seed it on a dedicated
# organization that has the product_catalog integration enabled, keeping
# Hooli as the legacy (v1) demo so the two flows never mix.
#
# NOTE: see 00_seed_config.rb — LAGO_SEED_ORGS alone skips this organization,
# set LAGO_SEED_ORG_CATALOG to seed it under another name.
org_data = SeedOrganizations.product_catalog_config
return if org_data.nil?

gavin = User.find_by!(email: "gavin@hooli.com")

name, id, api_key_value = org_data.values_at(:name, :id, :api_key)
entity_name, entity_code = org_data.values_at(:billing_entity_name, :billing_entity_code)

organization = Organization.find_by(name:) || Organization.create!(id:, name:)
organization.update!(
  premium_integrations: Organization::PREMIUM_INTEGRATIONS,
  feature_flags: organization.feature_flags.to_a | ["product_catalog"],
  invoice_footer: "#{entity_name} is a fictional company on the product catalog."
)

BillingEntity.find_or_create_by!(organization:, name: entity_name, code: entity_code).update!(
  email: "gavin@hooli.com",
  email_settings: BillingEntity::EMAIL_SETTINGS
)

membership = Membership.find_or_create_by!(user: gavin, organization:)
MembershipRole.find_or_create_by!(membership:, organization:, role: Role.find_by!(admin: true))

unless organization.api_keys.exists?
  api_key = organization.api_keys.create!(name: "#{entity_name} Key", permissions: ApiKey.default_permissions)
  api_key.update_columns(value: api_key_value) if api_key_value # rubocop:disable Rails/SkipsModelValidations
end

unless ProductCategory.exists?(organization:, code: "cloud_platform")
  # A billable metric with a filter, to back a usage product and a product filter.
  api_calls_bm = BillableMetric.find_by(organization:, code: "catalog_api_calls") ||
    BillableMetrics::CreateService.call!(
      organization_id: organization.id,
      name: "API calls",
      aggregation_type: "count_agg",
      code: "catalog_api_calls",
      filters: [{key: "region", values: %w[us eu]}]
    ).billable_metric

  region_filter = api_calls_bm.filters.find_by(key: "region")

  product_category = ProductCategories::CreateService.call!(
    organization:,
    params: {
      name: "Cloud Platform",
      code: "cloud_platform",
      description: "Seeded product catalog example"
    }
  ).product_category

  usage_item = Products::CreateService.call!(
    organization:,
    params: {
      name: "API calls",
      code: "api_calls",
      product_type: "metered",
      product_category_id: product_category.id,
      billable_metric_id: api_calls_bm.id
    }
  ).product

  Products::CreateService.call!(
    organization:,
    params: {
      name: "Platform fee",
      code: "platform_fee",
      product_type: "fixed",
      product_category_id: product_category.id
    }
  )

  ProductFilters::CreateService.call!(
    product: usage_item,
    params: {
      name: "EU traffic",
      code: "eu_traffic",
      values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]
    }
  )

  rate_card = RateCards::CreateService.call!(
    product: usage_item,
    params: {
      name: "Standard USD",
      code: "standard_usd",
      currency: "USD"
    }
  ).rate_card

  RateCardRates::CreateService.call!(
    rate_card:,
    params: {
      code: "rate_1",
      effective_from: Time.current.beginning_of_day,
      rate_model: "standard",
      rate_properties: {amount: "0.01"},
      billing_interval_unit: "month"
    }
  )

  # Assign the rate card to a catalog plan so the catalog is wired into an offer.
  # CreateService takes the attributes as a single positional hash (it mirrors
  # the controller's permitted params), so pass them wrapped, not as keywords.
  catalog_plan = CatalogPlans::CreateService.call!({
    organization_id: organization.id,
    name: "Growth",
    code: "growth",
    currency: "USD"
  }).catalog_plan

  PlanRateCards::CreateService.call!(
    catalog_plan:,
    params: {rate_card_code: rate_card.code}
  )
end
