# frozen_string_literal: true

# The product catalog is the v2 billing surface. Seed it on a dedicated
# organization that has the product_catalog integration enabled, keeping
# Hooli as the legacy (v1) demo so the two flows never mix.
gavin = User.find_by!(email: "gavin@hooli.com")

organization = Organization.find_by(name: "Hooli v2") ||
  Organization.create!(id: "33333333-4444-5555-6666-777777777777", name: "Hooli v2")
organization.update!(
  premium_integrations: Organization::PREMIUM_INTEGRATIONS,
  feature_flags: organization.feature_flags.to_a | ["product_catalog"],
  invoice_footer: "Hooli v2 is a fictional company on the product catalog."
)

BillingEntity.find_or_create_by!(organization:, name: "Hooli v2", code: "hooli_v2").update!(
  email: "gavin@hooli.com",
  email_settings: BillingEntity::EMAIL_SETTINGS
)

membership = Membership.find_or_create_by!(user: gavin, organization:)
MembershipRole.find_or_create_by!(membership:, organization:, role: Role.find_by!(admin: true))

unless organization.api_keys.exists?
  api_key = organization.api_keys.create!(name: "Hooli v2 Key", permissions: ApiKey.default_permissions)
  api_key.update_columns(value: "lago_key-hooli-v2-1234567890") # rubocop:disable Rails/SkipsModelValidations
end

unless Product.exists?(organization:, code: "cloud_platform")
  # A billable metric with a filter, to back a usage product item and a product item filter.
  api_calls_bm = BillableMetric.find_by(organization:, code: "catalog_api_calls") ||
    BillableMetrics::CreateService.call!(
      organization_id: organization.id,
      name: "API calls",
      aggregation_type: "count_agg",
      code: "catalog_api_calls",
      filters: [{key: "region", values: %w[us eu]}]
    ).billable_metric

  region_filter = api_calls_bm.filters.find_by(key: "region")

  product = Products::CreateService.call!(
    organization:,
    params: {
      name: "Cloud Platform",
      code: "cloud_platform",
      description: "Seeded product catalog example"
    }
  ).product

  usage_item = ProductItems::CreateService.call!(
    organization:,
    params: {
      name: "API calls",
      code: "api_calls",
      item_type: "usage",
      product_id: product.id,
      billable_metric_id: api_calls_bm.id
    }
  ).product_item

  ProductItems::CreateService.call!(
    organization:,
    params: {
      name: "Platform fee",
      code: "platform_fee",
      item_type: "fixed",
      product_id: product.id
    }
  )

  ProductItemFilters::CreateService.call!(
    product_item: usage_item,
    params: {
      name: "EU traffic",
      code: "eu_traffic",
      values: [{billable_metric_filter_id: region_filter.id, value: "eu"}]
    }
  )

  rate_card = RateCards::CreateService.call!(
    product_item: usage_item,
    params: {
      name: "Standard USD",
      code: "standard_usd",
      currency: "USD"
    }
  ).rate_card

  RateCardRates::CreateService.call!(
    rate_card:,
    params: {
      effective_datetime: 1.month.ago,
      rate_model: "standard",
      rate_properties: {amount: "0.01"},
      billing_interval_unit: "month"
    }
  )

  platform_fee_card = RateCards::CreateService.call!(
    product_item: ProductItem.find_by!(organization:, code: "platform_fee"),
    params: {
      name: "Platform fee USD",
      code: "platform_fee_usd",
      currency: "USD"
    }
  ).rate_card

  RateCardRates::CreateService.call!(
    rate_card: platform_fee_card,
    params: {
      effective_datetime: 1.month.ago,
      rate_model: "standard",
      rate_properties: {amount: "99"},
      billing_interval_unit: "month"
    }
  )

  # Assign the rate cards to a plan so the catalog is wired into an offer.
  plan = Plans::CreateService.call!({
    organization_id: organization.id,
    name: "Growth",
    code: "growth",
    amount_currency: "USD",
    pricing_type: "product_catalog"
  }).plan

  usage_entry = PlanRateCards::CreateService.call!(
    plan:,
    params: {rate_card_code: rate_card.code}
  ).plan_rate_card

  PlanRateCards::CreateService.call!(
    plan:,
    params: {rate_card_code: platform_fee_card.code, units: 1}
  )

  # Phases must be authored before the first subscription: a subscribed plan
  # is immutable (cards, phases and rates all lock).
  RatePhases::ReplaceService.call!(
    plan_rate_card: usage_entry,
    phases_params: [
      {
        position: 1,
        name: "Launch offer",
        billing_interval_cycle_count: 3,
        rate_override: {rate_model: "standard", rate_properties: {amount: "0.005"}}
      },
      {position: 2, name: "Standard", billing_interval_cycle_count: nil}
    ]
  )

  billing_entity = organization.billing_entities.find_by!(code: "hooli_v2")

  # An active subscription: materialization gives each plan card its own
  # billing lifecycle on the subscription, pricing stays on the plan.
  richard = Customer.create_with(
    name: "Richard Hendricks",
    currency: "USD",
    email: "richard@piedpiper.com"
  ).find_or_create_by!(organization:, billing_entity:, external_id: "cust_hooli_v2_1")

  active_subscription = Subscription.create_with(
    organization:,
    started_at: 1.month.ago,
    subscription_at: 1.month.ago,
    status: :active,
    billing_time: :anniversary
  ).find_or_create_by!(customer: richard, plan:, external_id: "sub_hooli_v2_1")

  Subscriptions::ProductCatalog::MaterializeService.call!(subscription: active_subscription)

  # A pending subscription still in its authoring window: rate cards and
  # phases can be added, edited or removed until activation.
  monica = Customer.create_with(
    name: "Monica Hall",
    currency: "USD",
    email: "monica@raviga.com"
  ).find_or_create_by!(organization:, billing_entity:, external_id: "cust_hooli_v2_2")

  pending_subscription = Subscription.create_with(
    organization:,
    subscription_at: 1.month.from_now,
    status: :pending,
    billing_time: :anniversary
  ).find_or_create_by!(customer: monica, plan:, external_id: "sub_hooli_v2_2")

  negotiated_entry = SubscriptionRateCards::CreateService.call!(
    subscription: pending_subscription,
    params: {rate_card_code: platform_fee_card.code, units: 1, started_at: 1.month.from_now.iso8601}
  ).subscription_rate_card

  RatePhases::ReplaceService.call!(
    subscription_rate_card: negotiated_entry,
    phases_params: [
      {
        position: 1,
        name: "Negotiated intro",
        billing_interval_cycle_count: 3,
        rate_override: {rate_model: "standard", rate_properties: {amount: "49"}}
      },
      {position: 2, name: "Standard", billing_interval_cycle_count: nil}
    ]
  )
end
