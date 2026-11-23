# frozen_string_literal: true

module BillingEngineMigrations
  class ConvertPlansService < BaseService
    Result = BaseResult[:plans]

    PlanReport = Data.define(:plan_code, :catalog_plan_code, :outcome, :error, :entries, :gaps)
    Entry = Data.define(:product, :product_filter, :rate_card, :rate, :units)

    ProductConflictError = Class.new(StandardError)

    RATE_CODE = "v1"

    PLAN_INTERVALS = {
      "weekly" => {billing_interval_unit: "week", billing_interval_count: 1},
      "monthly" => {billing_interval_unit: "month", billing_interval_count: 1},
      "quarterly" => {billing_interval_unit: "month", billing_interval_count: 3},
      "semiannual" => {billing_interval_unit: "month", billing_interval_count: 6},
      "yearly" => {billing_interval_unit: "year", billing_interval_count: 1}
    }.freeze

    MONTHLY_INTERVAL = PLAN_INTERVALS["monthly"]

    def initialize(migration:, dry_run: true)
      @migration = migration
      @dry_run = dry_run
      super
    end

    def call
      result.plans = []
      return result unless migration.shadowing?

      migration.plan_mapping.sort.each { |plan_code, catalog_plan_code| convert(plan_code, catalog_plan_code) }

      result
    end

    private

    attr_reader :migration, :dry_run

    delegate :organization, :shadow_organization, to: :migration

    def convert(plan_code, catalog_plan_code)
      report = {plan_code:, catalog_plan_code:, error: nil, entries: [], gaps: []}

      plan = organization.plans.parents.find_by(code: plan_code)
      return add_report(**report, outcome: :failed, error: "plan_not_found") unless plan
      return add_report(**report, outcome: :skipped) if shadow_organization.catalog_plans.exists?(code: catalog_plan_code)

      report[:gaps] = gaps(plan)

      missing_metrics = plan.billable_metrics.distinct.pluck(:code) - shadow_metrics_by_code.keys
      if missing_metrics.any?
        return add_report(**report, outcome: :failed, error: "billable_metrics_not_copied: #{missing_metrics.sort.join(", ")}")
      end

      report[:entries] = entries(plan, catalog_plan_code)
      return add_report(**report, outcome: :would_create) if dry_run

      create_catalog_plan(plan, catalog_plan_code, report[:entries])
      add_report(**report, outcome: :created)
    rescue BaseService::FailedResult, ActiveRecord::RecordInvalid, ProductConflictError => e
      add_report(**report, outcome: :failed, error: e.message)
    end

    def create_catalog_plan(plan, catalog_plan_code, entries)
      ActiveRecord::Base.transaction do
        catalog_plan = CatalogPlans::CreateService.call!(
          {
            organization_id: shadow_organization.id,
            code: catalog_plan_code,
            name: plan.name,
            description: plan.description,
            invoice_display_name: plan.invoice_display_name,
            currency: plan.amount_currency,
            tax_codes: plan.taxes.map(&:code)
          }
        ).catalog_plan

        entries.each { |entry| attach_rate_card(catalog_plan, entry) }
      end
    end

    def attach_rate_card(catalog_plan, entry)
      product = find_or_create_product(entry.product)
      product_filter = entry.product_filter && find_or_create_product_filter(product, entry.product_filter)

      rate_card = RateCards::CreateService.call!(
        product:,
        params: entry.rate_card.merge(product_filter_id: product_filter&.id)
      ).rate_card
      create_rate(rate_card, entry.rate)

      PlanRateCards::CreateService.call!(catalog_plan:, params: {rate_card_code: rate_card.code, units: entry.units})
    end

    def find_or_create_product(params)
      product = shadow_organization.products.find_by(code: params[:code])
      return Products::CreateService.call!(organization: shadow_organization, params:).product unless product

      if product.product_type != params[:product_type] || product.billable_metric_id != params[:billable_metric_id]
        raise ProductConflictError, "product_exists_with_another_type_or_metric: #{product.code}"
      end

      product
    end

    def find_or_create_product_filter(product, params)
      wanted = normalized_filter_values(params[:values])
      existing = product.filters.includes(values: :billable_metric_filter).find do |filter|
        normalized_filter_values(filter.values.map { {key: it.key, value: it.value} }) == wanted
      end

      existing || ProductFilters::CreateService.call!(product:, params:).product_filter
    end

    # RateCardRates::CreateService refuses an effective date before today and full ranges: the copied
    # rate must price periods that started on V1, and V1 properties already hold their from_value.
    def create_rate(rate_card, params)
      rate_card.rates.create!(organization_id: rate_card.organization_id, **params)
    end

    def entries(plan, catalog_plan_code)
      effective_from = rate_effective_from(plan)

      fixed_charge_entries = plan.fixed_charges.parents.order(:code).preload(:add_on, :taxes).map do |fixed_charge|
        fixed_charge_entry(plan, catalog_plan_code, fixed_charge, effective_from)
      end
      metered_entries = plan.charges.parents.order(:code)
        .preload(:billable_metric, :taxes, filters: {values: :billable_metric_filter})
        .flat_map { |charge| charge_entries(plan, catalog_plan_code, charge, effective_from) }

      [subscription_fee_entry(plan, catalog_plan_code, effective_from), *fixed_charge_entries, *metered_entries]
    end

    def subscription_fee_entry(plan, catalog_plan_code, effective_from)
      Entry.new(
        product: {
          code: "#{catalog_plan_code}_subscription_fee",
          name: plan.name,
          description: plan.description,
          invoice_display_name: plan.invoice_display_name,
          product_type: "fixed",
          billable_metric_id: nil
        },
        product_filter: nil,
        rate_card: {
          code: "#{catalog_plan_code}_subscription_fee",
          name: plan.invoice_name,
          currency: plan.amount_currency,
          billing_timing: plan.pay_in_advance? ? "advance" : "arrears",
          proration: true
        },
        rate: {
          code: RATE_CODE,
          effective_from:,
          rate_model: "standard",
          rate_properties: {amount: Money.from_cents(plan.amount_cents.to_i, plan.amount_currency).to_d.to_s("F")},
          **PLAN_INTERVALS.fetch(plan.interval)
        },
        units: BigDecimal(1)
      )
    end

    def fixed_charge_entry(plan, catalog_plan_code, fixed_charge, effective_from)
      add_on = fixed_charge.add_on
      interval = plan.fixed_charges_billed_in_monthly_split_intervals? ? MONTHLY_INTERVAL : PLAN_INTERVALS.fetch(plan.interval)

      Entry.new(
        product: {
          code: add_on.code,
          name: add_on.name,
          description: add_on.description,
          invoice_display_name: add_on.invoice_display_name,
          product_type: "fixed",
          billable_metric_id: nil
        },
        product_filter: nil,
        rate_card: {
          code: "#{catalog_plan_code}_#{fixed_charge.code}",
          name: fixed_charge.invoice_display_name.presence || add_on.invoice_name,
          currency: plan.amount_currency,
          billing_timing: fixed_charge.pay_in_advance? ? "advance" : "arrears",
          proration: fixed_charge.prorated,
          tax_codes: fixed_charge.taxes.map(&:code).presence
        }.compact,
        rate: {
          code: RATE_CODE,
          effective_from:,
          rate_model: fixed_charge.charge_model,
          rate_properties: rate_properties(fixed_charge.charge_model, fixed_charge.properties),
          **interval
        },
        units: fixed_charge.units
      )
    end

    def charge_entries(plan, catalog_plan_code, charge, effective_from)
      billable_metric = charge.billable_metric
      product = {
        code: billable_metric.code,
        name: billable_metric.name,
        description: billable_metric.description,
        product_type: "metered",
        billable_metric_id: shadow_metrics_by_code.fetch(billable_metric.code).id
      }
      rate_card = {
        code: "#{catalog_plan_code}_#{charge.code}",
        name: charge.invoice_display_name.presence || billable_metric.name,
        currency: plan.amount_currency,
        billing_timing: charge.pay_in_advance? ? "advance" : "arrears",
        proration: charge.prorated,
        display_on_invoice: charge.invoiceable,
        regroup_paid_fees: charge.regroup_paid_fees,
        tax_codes: charge.taxes.map(&:code).presence
      }.compact
      rate = {
        code: RATE_CODE,
        effective_from:,
        rate_model: charge.charge_model,
        rate_properties: rate_properties(charge.charge_model, charge.properties),
        min_amount_cents: charge.min_amount_cents,
        **(plan.charges_billed_in_monthly_split_intervals? ? MONTHLY_INTERVAL : PLAN_INTERVALS.fetch(plan.interval))
      }

      default_entry = Entry.new(product:, product_filter: nil, rate_card:, rate:, units: nil)
      filter_entries = charge.filters.map do |charge_filter|
        filter_code = charge_filter.code.presence || ChargeFilter.generate_code(charge_filter.to_h)

        Entry.new(
          product:,
          product_filter: {
            code: filter_code,
            name: charge_filter.display_name,
            invoice_display_name: charge_filter.invoice_display_name,
            values: product_filter_values(charge_filter)
          },
          rate_card: rate_card.merge(code: "#{rate_card[:code]}_#{filter_code}"),
          rate: rate.merge(rate_properties: rate_properties(charge.charge_model, charge_filter.properties)),
          units: nil
        )
      end

      [default_entry] + filter_entries
    end

    # Catalog volume tiers start where the previous one ends, V1 ones a unit after it.
    def rate_properties(rate_model, properties)
      return properties unless rate_model == "volume"

      ranges = properties["volume_ranges"]
      adjacent_ranges = ranges.each_with_index.map do |range, index|
        range.merge("from_value" => index.zero? ? 0 : ranges[index - 1]["to_value"])
      end
      properties.merge("volume_ranges" => adjacent_ranges)
    end

    def product_filter_values(charge_filter)
      charge_filter.values.flat_map do |filter_value|
        key = filter_value.billable_metric_filter.key
        next [{key:, value: nil}] if filter_value.values == [ChargeFilterValue::ALL_FILTER_VALUES]

        filter_value.values.map { |value| {key:, value:} }
      end
    end

    def normalized_filter_values(values)
      values.map { |value| [value[:key], value[:value].to_s] }.sort
    end

    # Copied subscriptions start in the past, so the rate is effective from before any of them.
    def rate_effective_from(plan)
      [plan.created_at, plan.subscriptions.minimum(:started_at), plan.subscriptions.minimum(:subscription_at)].compact.min
    end

    def gaps(plan)
      gaps = []
      gaps << "trial_period" if plan.has_trial?
      gaps << "minimum_commitment" if plan.minimum_commitment
      gaps << "progressive_billing_thresholds" if plan.usage_thresholds.exists?
      gaps << "entitlements" if plan.entitlements.exists?
      gaps << "metadata" if plan.metadata&.value.present?

      plan.charges.parents.order(:code).preload(:applied_pricing_unit).each do |charge|
        gaps << "charge #{charge.code}: accepts_target_wallet" if charge.accepts_target_wallet
        gaps << "charge #{charge.code}: pricing_unit" if charge.applied_pricing_unit
        gaps << "charge #{charge.code}: invoice_display_name" if charge.invoice_display_name.present?
      end

      plan.fixed_charges.parents.order(:code).each do |fixed_charge|
        gaps << "fixed_charge #{fixed_charge.code}: invoice_display_name" if fixed_charge.invoice_display_name.present?
      end

      gaps
    end

    def shadow_metrics_by_code
      @shadow_metrics_by_code ||= shadow_organization.billable_metrics.index_by(&:code)
    end

    def add_report(outcome:, **report)
      result.plans << PlanReport.new(outcome:, **report)
    end
  end
end
