# frozen_string_literal: true

module Invoices
  class CustomerUsageService < BaseService
    Result = BaseResult[:invoice, :usage, :fees_taxes]

    # Recurring metrics of these types set use_from_boundary to false, so they aggregate all history
    # up to the upper boundary whatever lower boundary they are given.
    LIFETIME_BY_DEFAULT_AGGREGATIONS = %w[sum_agg unique_count_agg].freeze

    def initialize(
      customer:,
      subscription:,
      timestamp: Time.current,
      apply_taxes: true,
      with_cache: true,
      max_timestamp: nil,
      calculate_projected_usage: false,
      with_zero_units_filters: true,
      usage_filters: UsageFilters::NONE
    )
      super

      @apply_taxes = apply_taxes
      @customer = customer
      @subscription = subscription
      @timestamp = timestamp # To not set this value if without disabling the cache
      @with_cache = with_cache
      @calculate_projected_usage = calculate_projected_usage
      @with_zero_units_filters = with_zero_units_filters
      @usage_filters = usage_filters

      # NOTE: used to force charges_to_datetime boundary
      @max_timestamp = max_timestamp
    end

    def self.with_external_ids(customer_external_id:, external_subscription_id:, organization_id:, apply_taxes: true,
      calculate_projected_usage: false, usage_filters: UsageFilters::NONE)
      customer = Customer.find_by!(external_id: customer_external_id, organization_id:)
      subscription = customer&.active_subscriptions&.find_by(external_id: external_subscription_id)
      new(customer:, subscription:, apply_taxes:, calculate_projected_usage:, usage_filters:)
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "customer")
    end

    def self.with_ids(organization_id:, customer_id:, subscription_id:, apply_taxes: true, calculate_projected_usage: false)
      customer = Customer.find_by(id: customer_id, organization_id:)
      subscription = customer&.active_subscriptions&.find_by(id: subscription_id)
      new(customer:, subscription:, apply_taxes:, calculate_projected_usage:)
    rescue ActiveRecord::RecordNotFound
      result.not_found_failure!(resource: "customer")
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer
      return result.not_allowed_failure!(code: "no_active_subscription") if subscription.blank?
      return result.not_allowed_failure!(code: "full_usage_not_allowed") if usage_filters.full_usage && !querying_full_usage_allowed
      return result.not_found_failure!(resource: "charge") if charges.empty? && usage_filters.has_charge_filter?

      result.usage = compute_usage
      result.invoice = invoice
      result
    rescue BaseService::ThrottlingError => error
      result.too_many_provider_requests_failure!(provider_name: error.provider_name, error:)
    end

    private

    attr_reader :customer, :invoice, :subscription, :timestamp, :apply_taxes, :with_cache, :max_timestamp, :calculate_projected_usage, :with_zero_units_filters
    attr_reader :usage_filters

    delegate :plan, to: :subscription
    delegate :billing_entity, to: :customer

    def charges
      return @charges if defined?(@charges)

      charges = subscription
        .plan
        .charges
        .joins(:billable_metric)
        .includes(:taxes, :applied_pricing_unit, billable_metric: :organization, filters: {values: :billable_metric_filter})
      if usage_filters.filter_by_charge_id.present?
        charges = charges.where(id: usage_filters.filter_by_charge_id)
      elsif usage_filters.filter_by_charge_code.present?
        charges = charges.where(code: usage_filters.filter_by_charge_code)
      elsif usage_filters.filter_by_metric_code.present?
        charges = charges.where(billable_metrics: {code: usage_filters.filter_by_metric_code})
      end
      @charges = charges
    end

    # NOTE: Since computing customer usage could take some time as it as to
    #       loop over a lot of records in database, the result is stored in a cache store.
    #       - Each charge result is stored in its own fragmented cache
    #       - The cache expiration is set to the end of the billing period
    #       - Cache will be automatically cleared if a new event is sent for a specific charge
    def compute_usage
      @invoice = Invoice.new(
        organization:,
        billing_entity:,
        customer:,
        issuing_date: boundaries.issuing_date,
        currency: plan.amount_currency
      )

      invoice.fees = compute_charge_fees

      if apply_taxes && customer_provider_taxation?
        compute_amounts_with_provider_taxes
      elsif apply_taxes
        compute_amounts
      else
        compute_amounts_without_tax
      end

      format_usage
    end

    def organization
      @organization ||= subscription.organization
    end

    def compute_charge_fees
      fees = []
      filters = event_filters(subscription, boundaries).filter_targets
      charges.find_each { |c| fees += charge_usage(c, filters[c.target_key] || {}) }
      return fees if usage_filters.has_charge_filter?

      fees.sort_by { |f| f.billable_metric.name.downcase }
    end

    def charge_usage(charge, applied_filters)
      cache_middleware = Subscriptions::ChargeCacheMiddleware.new(
        subscription:,
        charge:,
        to_datetime: boundaries.charges_to_datetime,
        cache: charge_cache_enabled?,
        full_usage: usage_filters.full_usage && !lifetime_by_default?(charge),
        last_seen_at: applied_filters
      )

      applied_boundaries = boundaries
      applied_boundaries = boundaries.dup.tap { it.max_timestamp = max_timestamp } if max_timestamp

      Fees::ChargeService
        .call!(
          invoice:,
          metered_item: Fees::ChargeService::MeteredItem.from_charge(charge:, boundaries: applied_boundaries),
          subscription:,
          cache_middleware:,
          filtered_aggregations: applied_filters.keys,
          options: Fees::ChargeService::Options.new(
            context: :current_usage,
            calculate_projected_usage:,
            with_zero_units_filters:,
            usage_filters:,
            # NOTE: current usage is computed on a non-persisted invoice, so adjusted fees never apply
            skip_adjusted_fees: true
          )
        )
        .fees
    end

    # A recurring sum or unique count aggregates all history whatever lower boundary it is given, so
    # its full usage is the number the ordinary current period entry already holds. Only the cache
    # key changes: the window it is computed over is irrelevant to the result.
    #
    # Pay in advance is excluded because find_cached_aggregation is scoped by the lower boundary,
    # and prorated because the period ratio is applied to it.
    def lifetime_by_default?(charge)
      return false unless usage_filters.full_usage
      return false if calculate_projected_usage || max_timestamp
      return false if charge.pay_in_advance? || charge.prorated?

      metric = charge.billable_metric
      metric.recurring? && LIFETIME_BY_DEFAULT_AGGREGATIONS.include?(metric.aggregation_type)
    end

    def boundaries
      return @boundaries if @boundaries.present?

      from = usage_filters.full_usage ? subscription.started_at : date_service.from_datetime
      charges_from = usage_filters.full_usage ? subscription.started_at : date_service.charges_from_datetime

      @boundaries = BillingPeriodBoundaries.new(
        from_datetime: from,
        to_datetime: date_service.to_datetime,
        charges_from_datetime: charges_from,
        charges_to_datetime: date_service.charges_to_datetime,
        issuing_date: date_service.next_end_of_period,
        charges_duration: date_service.charges_duration_in_days,
        timestamp:
      )
    end

    def date_service
      @date_service ||= Subscriptions::DatesService.new_instance(subscription, timestamp, current_usage: true)
    end

    def compute_amounts
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)
      plan = subscription.plan

      invoice.fees.each do |fee|
        taxes_result = Fees::ApplyTaxesService.call(fee:, customer:, plan:)
        taxes_result.raise_if_error!
      end

      taxes_result = Invoices::ApplyTaxesService.call(invoice:)
      taxes_result.raise_if_error!

      invoice.total_amount_cents = invoice.fees_amount_cents + invoice.taxes_amount_cents
    end

    def compute_amounts_without_tax
      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)
      invoice.taxes_amount_cents = 0
      invoice.taxes_rate = 0
      invoice.total_amount_cents = invoice.fees_amount_cents
    end

    def compute_amounts_with_provider_taxes
      # NOTE: Only fees with a positive amount can incur tax, so non-taxable fees are
      #       excluded from the provider request. This also keeps the payload under the
      #       provider line-item limit (Anrok/Avalara reject payloads above 1200 items).
      #       Excluded fees owe no tax and keep their default zero taxes in the usage response.
      taxable_fees = invoice.fees.select(&:taxable?)

      # NOTE: With no taxable fees the provider request would carry an empty line-item
      #       array, which Anrok/Avalara reject. There is no tax to compute, so fall back
      #       to the zero-tax path and skip the provider entirely.
      return compute_amounts_without_tax if taxable_fees.empty?

      invoice.fees_amount_cents = invoice.fees.sum(&:amount_cents)

      # NOTE: Set the sub total so Invoices::ApplyProviderTaxesService prorates taxes_rate
      #       by amount (like persisted invoices) instead of falling back to its zero-amount
      #       count-based branch, which would dilute the rate with the excluded non-taxable fees.
      invoice.sub_total_excluding_taxes_amount_cents = invoice.fees_amount_cents

      taxes_result = Integrations::Aggregator::Taxes::Invoices::CreateDraftService.call(invoice:, fees: taxable_fees)

      return result.validation_failure!(errors: {tax_error: [taxes_result.error.message]}) unless taxes_result.success?

      result.fees_taxes = taxes_result.fees

      taxable_fees.each do |fee|
        fee_taxes = result.fees_taxes.find do |item|
          item.item_key == fee.item_key
        end

        res = Fees::ApplyProviderTaxesService.call(fee:, fee_taxes:)
        res.raise_if_error!
      end

      res = Invoices::ApplyProviderTaxesService.call(invoice:, provider_taxes: result.fees_taxes)
      res.raise_if_error!

      invoice.total_amount_cents = invoice.fees_amount_cents + invoice.taxes_amount_cents
    end

    def format_usage
      SubscriptionUsage.new(
        from_datetime: boundaries.charges_from_datetime.iso8601,
        to_datetime: boundaries.charges_to_datetime.iso8601,
        issuing_date: invoice.issuing_date.iso8601,
        currency: invoice.currency,
        amount_cents: invoice.fees_amount_cents,
        total_amount_cents: invoice.total_amount_cents,
        taxes_amount_cents: invoice.taxes_amount_cents,
        fees: invoice.fees
      )
    end

    def customer_provider_taxation?
      @customer_provider_taxation ||= invoice.customer.tax_customer
    end

    # Only the charges being computed are billed, so restricting the event lookup to their codes
    # avoids resolving combinations for the rest of the plan. The ingestion timestamps are requested
    # only when the charge cache can actually read them.
    def event_filters(subscription, boundaries)
      Events::BillingPeriodFilterService.for_charges!(
        subscription:,
        boundaries:,
        codes: filtered_metric_codes,
        with_last_seen_at: charge_cache_enabled?
      )
    end

    # nil when every charge of the plan is computed, so the whole plan is looked up as before.
    def filtered_metric_codes
      return nil unless usage_filters.has_charge_filter?

      charges.except(:includes).joins(:billable_metric).distinct.pluck("billable_metrics.code")
    end

    # Single gate for the charge cache: it drives both the middleware passed to Fees::ChargeService
    # and whether the ingestion timestamps are requested. The two must never diverge, because a nil
    # timestamp written into a live cache stays valid forever (see Events::BillingPeriodFilterService).
    # Usage filtered by group is never cached, as its fees are a subset of the charge fees.
    def charge_cache_enabled?
      with_cache &&
        usage_filters.filter_by_group.blank? &&
        (!usage_filters.full_usage || full_usage_cache_enabled?)
    end

    # Full usage is cached only with lazy validation, the one invalidation that clears its key.
    def full_usage_cache_enabled?
      organization.granular_lifetime_usage_enabled? &&
        organization.feature_flag_enabled?(:lazy_charge_usage_cache) &&
        !usage_filters.skip_grouping &&
        usage_filters.filter_by_presentation.nil?
    end

    def querying_full_usage_allowed
      return false unless organization.granular_lifetime_usage_enabled?

      any_filter_present = usage_filters.has_charge_filter? || usage_filters.filter_by_group.present?
      subscription_has_prorated_charges = charges.where(prorated: true).exists?

      # full usage is only allowed for subscriptions without prorated charges
      # and only when filtering by charge or by group
      !subscription_has_prorated_charges && any_filter_present
    end
  end
end
