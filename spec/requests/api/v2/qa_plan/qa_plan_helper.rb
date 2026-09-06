# frozen_string_literal: true

# Fixture builder for the QA acceptance plan of the v2 product-catalog billing engine.
#
# The plan (executed against staging 2026-08-10..13) describes one baseline seed and
# expresses every scenario as a delta on it. `qa_seed` is that baseline: a fixed product
# priced by a standard 30.00 monthly arrears rate, 5 units on the plan entry, so a full
# period bills 150.00. Each scenario overrides only what its own delta names.
module QaPlanSeeds
  Seed = Data.define(
    :customer,
    :plan,
    :product,
    :rate_card,
    :rates,
    :plan_rate_card,
    :subscription,
    :subscription_rate_card
  ) do
    def external_id
      subscription.external_id
    end

    def rate
      rates.first
    end
  end

  BASELINE_RATES = [{amount: "30.00", effective_from: "2026-01-01"}].freeze

  # BC — [case, interval count, unit, period 1 from/to, period 2 from/to, 1st invoice date]
  BC_MATRIX = [
    ["BCa", 1, "day", %w[2026-08-10 2026-08-10], %w[2026-08-11 2026-08-11], "2026-08-11"],
    ["BCb", 45, "day", %w[2026-08-10 2026-09-23], %w[2026-09-24 2026-11-07], "2026-09-24"],
    ["BCc", 1, "week", %w[2026-08-10 2026-08-16], %w[2026-08-17 2026-08-23], "2026-08-17"],
    ["BCd", 4, "week", %w[2026-08-10 2026-09-06], %w[2026-09-07 2026-10-04], "2026-09-07"],
    ["BCe", 3, "month", %w[2026-08-10 2026-11-09], %w[2026-11-10 2027-02-09], "2026-11-10"],
    ["BCf", 6, "month", %w[2026-08-10 2027-02-09], %w[2027-02-10 2027-08-09], "2027-02-10"],
    ["BCg", 1, "year", %w[2026-08-10 2027-08-09], %w[2027-08-10 2028-08-09], "2027-08-10"],
    ["BCh", 2, "year", %w[2026-08-10 2028-08-09], %w[2028-08-10 2030-08-09], "2028-08-10"]
  ].freeze

  # CS1a / CS1c — [row, timing, proration, anchor, first period from/to, expected cents]
  CS1A_MATRIX = [
    [1, "advance", false, "2026-08-10", ["2026-08-10T00:00:00Z", "2026-09-09T23:59:59Z"], 15_000],
    [2, "advance", true, "2026-08-10", ["2026-08-10T00:00:00Z", "2026-09-09T23:59:59Z"], 15_000],
    [3, "advance", false, "2026-09-01", ["2026-08-10T00:00:00Z", "2026-08-31T23:59:59Z"], 15_000],
    [4, "advance", true, "2026-09-01", ["2026-08-10T00:00:00Z", "2026-08-31T23:59:59Z"], 10_645],
    [5, "arrears", false, "2026-08-10", ["2026-08-10T00:00:00Z", "2026-09-09T23:59:59Z"], 15_000],
    [6, "arrears", true, "2026-08-10", ["2026-08-10T00:00:00Z", "2026-09-09T23:59:59Z"], 15_000],
    [7, "arrears", false, "2026-09-01", ["2026-08-10T00:00:00Z", "2026-08-31T23:59:59Z"], 15_000],
    [8, "arrears", true, "2026-09-01", ["2026-08-10T00:00:00Z", "2026-08-31T23:59:59Z"], 10_645]
  ].freeze

  CS1C_MATRIX = [
    [1, "advance", false, "2026-09-01", ["2026-09-01T00:00:00Z", "2026-09-30T23:59:59Z"], 15_000],
    [2, "advance", true, "2026-09-01", ["2026-09-01T00:00:00Z", "2026-09-30T23:59:59Z"], 15_000],
    [3, "advance", false, "2026-09-15", ["2026-09-01T00:00:00Z", "2026-09-14T23:59:59Z"], 15_000],
    [4, "advance", true, "2026-09-15", ["2026-09-01T00:00:00Z", "2026-09-14T23:59:59Z"], 6_774],
    [5, "arrears", false, "2026-09-01", ["2026-09-01T00:00:00Z", "2026-09-30T23:59:59Z"], 15_000],
    [6, "arrears", true, "2026-09-01", ["2026-09-01T00:00:00Z", "2026-09-30T23:59:59Z"], 15_000],
    [7, "arrears", false, "2026-09-15", ["2026-09-01T00:00:00Z", "2026-09-14T23:59:59Z"], 15_000],
    [8, "arrears", true, "2026-09-15", ["2026-09-01T00:00:00Z", "2026-09-14T23:59:59Z"], 6_774]
  ].freeze

  # rubocop:disable Metrics/ParameterLists
  def qa_seed(
    id:,
    timing: "arrears",
    proration: false,
    units: 5,
    subscription_at: "2026-08-10",
    anchor: nil,
    rates: BASELINE_RATES,
    phases: [],
    customer: nil,
    plan: nil,
    subscription: nil,
    pending: false,
    card_extra: {}
  )
    starts_at = Time.zone.parse("#{subscription_at} 00:00:00")
    seed_customer = customer || create(:customer, organization:, currency: "USD")
    seed_plan = plan || create(:plan, :product_catalog, organization:, amount_currency: "USD", code: "plan_#{id}")
    product = create(:product, :fixed, organization:, code: "seat_fee_#{id}")

    rate_card = create(
      :rate_card,
      organization:,
      product:,
      code: "card_#{id}",
      currency: "USD",
      billing_timing: timing,
      proration:,
      **card_extra
    )

    seed_rates = rates.each_with_index.map do |spec, index|
      create(
        :rate_card_rate,
        organization:,
        rate_card:,
        code: spec[:code] || "rate_#{id}_v#{index + 1}",
        effective_from: Time.zone.parse("#{spec[:effective_from] || "2026-01-01"} 00:00:00"),
        rate_model: spec[:rate_model] || "standard",
        rate_properties: spec[:rate_properties] || {"amount" => spec[:amount] || "30.00"},
        min_amount_cents: spec[:min_amount_cents] || 0,
        applied_pricing_unit_conversion_rate: spec[:conversion],
        billing_interval_count: spec[:interval_count] || 1,
        billing_interval_unit: spec[:interval_unit] || "month"
      )
    end

    plan_rate_card = create(:plan_rate_card, organization:, plan: seed_plan, rate_card:, units:)
    # The write path (PlanRateCards::CreateService) always materializes an implicit
    # "default" phase, which is the `rate_phase_code: "default"` the plan records.
    build_rate_phases(plan_rate_card, phases.presence || [{code: "default", position: 1}])

    seed_subscription = subscription || build_qa_subscription(
      id:, plan: seed_plan, customer: seed_customer, starts_at:, pending:
    )

    subscription_rate_card = create(
      :subscription_rate_card,
      organization:,
      subscription: seed_subscription,
      customer: seed_customer,
      rate_card:,
      units:,
      billing_anchor_date: Date.parse(anchor || subscription_at),
      started_at: starts_at,
      next_billing_at: starts_at
    )

    Seed.new(
      customer: seed_customer,
      plan: seed_plan,
      product:,
      rate_card:,
      rates: seed_rates,
      plan_rate_card:,
      subscription: seed_subscription,
      subscription_rate_card:
    )
  end
  # rubocop:enable Metrics/ParameterLists

  # A second card on the same plan and subscription (X7, X8). The plan's rule is one card
  # per product, so this gets its own product.
  def qa_extra_card(seed:, id:, amount:, units: 1, interval_unit: "month")
    product = create(:product, :fixed, organization:, code: "support_fee_#{id}")
    rate_card = create(
      :rate_card,
      organization:,
      product:,
      code: "card_#{id}_support",
      currency: "USD",
      billing_timing: "arrears",
      proration: false
    )
    create(
      :rate_card_rate,
      organization:,
      rate_card:,
      code: "rate_#{id}_support_v1",
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      rate_properties: {"amount" => amount},
      billing_interval_count: 1,
      billing_interval_unit: interval_unit
    )
    support_plan_rate_card = create(:plan_rate_card, organization:, plan: seed.plan, rate_card:, units:)
    build_rate_phases(support_plan_rate_card, [{code: "default", position: 1}])

    create(
      :subscription_rate_card,
      organization:,
      subscription: seed.subscription,
      customer: seed.customer,
      rate_card:,
      units:,
      billing_anchor_date: seed.subscription_rate_card.billing_anchor_date,
      started_at: seed.subscription_rate_card.started_at,
      next_billing_at: seed.subscription_rate_card.started_at
    )
  end

  def build_qa_subscription(id:, plan:, customer:, starts_at:, pending: false)
    attributes = {
      organization:,
      customer:,
      plan:,
      external_id: "sub_#{id}",
      subscription_at: starts_at
    }

    if pending
      create(:subscription, :pending, **attributes)
    else
      create(:subscription, **attributes, started_at: starts_at, activated_at: starts_at)
    end
  end

  def build_rate_phases(plan_rate_card, phases)
    phases.each do |phase|
      override = phase[:override] && create(
        :rate_override,
        organization:,
        rate_model: phase[:override][:rate_model] || "standard",
        rate_properties: phase[:override][:rate_properties] || {"amount" => phase[:override][:amount]},
        billing_interval_count: phase[:override][:interval_count],
        billing_interval_unit: phase[:override][:interval_unit]
      )

      create(
        :rate_phase,
        organization:,
        plan_rate_card:,
        code: phase[:code],
        position: phase[:position],
        billing_interval_cycle_count: phase[:cycle_count],
        rate_override: override
      )
    end
  end

  # Step 1 of every scenario: the dry run. Returns nothing — read `json`.
  def qa_cycles(seed, start_on:, end_on:, at: nil)
    ids = Array.wrap(seed).map { it.is_a?(String) ? it : it.external_id }
    travel_to(Time.zone.parse("#{at || start_on} 00:00:00")) do
      get_with_token(
        organization,
        "/api/v2/subscriptions/cycles",
        {subscription_external_ids: ids, start_on:, end_on:}
      )
    end
  end

  # Step 2: the billing run.
  def qa_bill(seed, start_on:, end_on:, at: nil)
    ids = Array.wrap(seed).map { it.is_a?(String) ? it : it.external_id }
    travel_to(Time.zone.parse("#{at || end_on} 00:00:00")) do
      post_with_token(
        organization,
        "/api/v2/subscriptions/bill",
        {subscription_external_ids: ids, start_on:, end_on:}
      )
    end
  end

  # Invoice totals in cents, ordered by the period they cover — the shape every
  # expected-invoice table in the plan is written in. Creation order is not period order:
  # the consumer groups pending cycles into invoices by billing date and emits the groups
  # in hash order.
  def qa_invoices(customer)
    customer.invoices
      .includes(:invoice_subscriptions)
      .sort_by { |invoice| invoice.invoice_subscriptions.map(&:from_datetime).min }
  end

  def qa_invoice_totals(customer)
    qa_invoices(customer).map(&:total_amount_cents)
  end

  def qa_issuing_dates(customer)
    qa_invoices(customer).map { it.issuing_date.to_s }
  end

  def qa_cycle_rows
    BillingCycle.order(:period_from, :billing_at).map do |cycle|
      {
        from: cycle.period_from.iso8601,
        to: cycle.period_to.iso8601,
        billing_at: cycle.billing_at.iso8601,
        rate: cycle.rate_card_rate&.code
      }
    end
  end

  def qa_fees
    Fee.joins(:invoice).order("invoices.created_at", "fees.created_at").to_a
  end
end
