# frozen_string_literal: true

module Fees
  class ChargeService < BaseService
    Result = BaseResult[:fees, :cached_aggregations]

    def initialize(
      invoice:,
      metered_item:,
      billing_context:,
      cache_middleware: nil,
      filtered_aggregations: nil,
      options: nil,
      plan: nil,
      customer: nil
    )
      @invoice = invoice
      @metered_item = metered_item
      @billing_context = billing_context
      @options = options || Options.default
      @plan = plan
      @customer = customer

      validate!

      @cache_middleware = if metered_item.billing_segment
        nil
      else
        cache_middleware || Subscriptions::ChargeCacheMiddleware.new(
          subscription:,
          charge: metered_item.charge,
          to_datetime: metered_item.boundaries.charges_to_datetime,
          cache: false
        )
      end
      @filtered_aggregations = filtered_aggregations

      super(nil)
    end

    def call
      return result if !options.current_usage? && already_billed?

      init_metered_items_fees
      return result if options.current_usage?
      return result unless result.success?

      if invoice.nil? || !invoice.progressive_billing?
        init_true_up_fee
      end

      return result unless result.success?

      ActiveRecord::Base.transaction do
        result.fees.reject! { |f| !should_persist_fee?(f, result.fees) }
        next if options.invoice_preview?

        result.fees.each do |fee|
          fee.save!

          next unless invoice&.draft? && fee.true_up_parent_fee.nil? && adjusted_fee(
            charge_filter: fee.charge_filter,
            grouped_by: fee.grouped_by
          )

          adjusted_fee(charge_filter: fee.charge_filter, grouped_by: fee.grouped_by).update!(fee:)
        end
      end

      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice, :metered_item, :billing_context, :cache_middleware, :filtered_aggregations, :options, :plan, :customer

    delegate :subscription, to: :billing_context

    def init_metered_items_fees
      result.fees = []

      metered_item.billing_items.each do |item|
        init_fees(selected_metered_item: item)
        unless result.success?
          return result
        end
      end
    end

    def init_fees(selected_metered_item:)
      if skip_unused_filter?(selected_metered_item)
        fees = []
      else
        fees = compute_fees_with_cache(selected_metered_item:)
        # NOTE: nil means the aggregation or the charge model failed, result carries the error
        return if fees.nil?
      end

      if fees.empty? && skip_caching_of_non_persistable_fee?
        fees = hydrate_non_persistable_fees(selected_metered_item:)
      end

      # Preserve preloaded associations on all fees (including cached ones) to avoid N+1 queries
      fees.each do |fee|
        fee.association(:billable_metric).target = selected_metered_item.billable_metric
        if selected_metered_item.filter_id
          fee.association(selected_metered_item.filter_association).target = selected_metered_item.selected_filter
        end
        unless selected_metered_item.billing_segment
          fee.association(:charge).target = selected_metered_item.charge
        end
      end

      result.fees.concat(fees.compact)
    end

    # NOTE: When the billing period pre-filtering (Events::BillingPeriodFilterService) reports
    #       that no event matches this filter in the period, the fee can only have zero units.
    #       The cache round-trip and the bypassed aggregation are skipped and the zero-units fee
    #       is hydrated in memory instead. Scoped to current usage: on invoicing, adjusted fees
    #       on draft invoices can target filters without any usage.
    #       Recurring metrics always aggregate as usage carries over from previous periods.
    def skip_unused_filter?(selected_metered_item)
      return false unless options.current_usage?
      return false if filtered_aggregations.nil?
      return false if selected_metered_item.billable_metric.recurring?

      !filtered_aggregations.include?(selected_metered_item.filter_id)
    end

    def compute_fees_with_cache(selected_metered_item:)
      if cache_middleware
        cache_middleware.call(charge_filter: selected_metered_item.charge_filter) do
          fees = compute_fees(selected_metered_item:)
          if fees.nil?
            return
          end
          fees
        end
      else
        compute_fees(selected_metered_item:)
      end
    end

    def compute_fees(selected_metered_item:)
      aggregation_result = aggregator(selected_metered_item:).aggregate(
        options: selected_metered_item.aggregation_options(current_usage: options.current_usage?)
      )

      unless aggregation_result.success?
        result.fail_with_error!(aggregation_result.error)
        return
      end

      charge_model_result = apply_charge_model(aggregation_result:, selected_metered_item:)
      unless charge_model_result.success?
        result.fail_with_error!(charge_model_result.error)
        return
      end

      breakdowns_by_group = breakdowns_by_grouped_by(aggregation_result.breakdowns, charge_model_result)

      if selected_metered_item.billable_metric.recurring?
        persist_recurring_value(
          aggregation_result.aggregations || [aggregation_result],
          selected_metered_item,
          breakdowns_by_group
        )
      end

      charge_fees = fees_from_charge_model_result(
        charge_model_result,
        selected_metered_item:,
        breakdowns_by_group:
      )

      filter_non_persistable_fees_for_caching(charge_fees)
    end

    def skip_caching_of_non_persistable_fee?
      options.current_usage?
    end

    def hydrate_non_persistable_fees(selected_metered_item:)
      zero_aggregation = aggregator(selected_metered_item:).empty_results

      charge_model_result = ChargeModels::Factory.new_instance(
        pricing_structure: selected_metered_item.pricing_structure,
        aggregation_result: zero_aggregation,
        period_ratio: selected_metered_item.elapsed_period_ratio,
        calculate_projected_usage: options.calculate_projected_usage
      ).apply

      fees_from_charge_model_result(charge_model_result, selected_metered_item:, breakdowns_by_group: {})
    end

    def fees_from_charge_model_result(charge_model_result, selected_metered_item:, breakdowns_by_group:)
      charge_model_result.grouped_results.map do |amount_result|
        # TODO: check if this is still needed as we now skip certain zero units fees
        if options.current_usage? && selected_metered_item.selected_filter && amount_result.units.zero? && !options.with_zero_units_filters
          next
        end

        adjusted = applicable_adjusted_fee(amount_result:, selected_metered_item:)
        fee = init_fee(amount_result, selected_metered_item:, adjusted:)
        next if fee.nil?

        if adjusted.nil? || amount_result.units == fee.units
          build_breakdowns_for_fee(fee:, breakdowns_by_group:)
        end

        fee
      end.compact
    end

    def applicable_adjusted_fee(amount_result:, selected_metered_item:)
      return nil if options.current_usage?
      return nil unless invoice&.draft?

      adjusted = adjusted_fee(charge_filter: selected_metered_item.charge_filter, grouped_by: amount_result.grouped_by)
      return nil if adjusted.nil? || adjusted.adjusted_display_name?

      adjusted
    end

    def build_breakdowns_for_fee(fee:, breakdowns_by_group:)
      grouped_by = fee.grouped_by

      (breakdowns_by_group[grouped_by] || []).map do |breakdown|
        fee.presentation_breakdowns.build(
          presentation_by: breakdown[:groups],
          units: breakdown[:value],
          organization_id: metered_item.organization_id
        )
      end
    end

    def breakdowns_by_grouped_by(breakdowns, charge_model_result)
      charge_model_result.grouped_results.each_with_object({}) do |grouped_result, memo|
        grouped_by = grouped_result.grouped_by || {}
        next if memo.key?(grouped_by)

        grouped_by_keys = grouped_by.keys
        memo[grouped_by] = Array(breakdowns)
          .lazy
          .select { |b| b[:groups].slice(*grouped_by_keys) == grouped_by }
          .map { |b| {groups: b[:groups].except(*grouped_by_keys), value: b[:value]} }
          .to_a
      end
    end

    def filter_non_persistable_fees_for_caching(charge_fees)
      return charge_fees unless skip_caching_of_non_persistable_fee?

      charge_fees.filter { |f| should_persist_fee?(f, charge_fees) }
    end

    def init_fee(amount_result, selected_metered_item:, adjusted:)
      # NOTE: Build fee for case when there is adjusted fee and units or amount has been adjusted (see applicable_adjusted_fee method).
      # Base fee creation flow handles case when only name has been adjusted
      if adjusted
        adjustement_result = Fees::InitFromAdjustedChargeFeeService.call(
          adjusted_fee: adjusted,
          boundaries: selected_metered_item.boundaries,
          properties: selected_metered_item.properties
        )
        unless adjustement_result.success?
          result.fail_with_error!(adjustement_result.error)
          return nil
        end

        return adjustement_result.fee
      end

      amount = Fees::AmountsService.call(
        currency: selected_metered_item.currency,
        charge_model_result: amount_result,
        applied_pricing_unit: Fees::AmountsService::AppliedPricingUnit.from_applied_pricing_unit(selected_metered_item.applied_pricing_unit)
      ).amount

      # Prevent trying to create a fee with negative units or amount.
      if amount_result.units.negative? || amount_result.amount.negative?
        amount_result.full_units_number = amount_result.units = BigDecimal(0)
      end

      units = if options.current_usage? && (selected_metered_item.pay_in_advance? || selected_metered_item.prorated?)
        amount_result.current_usage_units
      elsif selected_metered_item.prorated?
        amount_result.full_units_number.nil? ? amount_result.units : amount_result.full_units_number
      else
        amount_result.units
      end

      new_fee = Fee.new(
        invoice:,
        organization_id: billing_context.organization_id,
        billing_entity_id: billing_context.applicable_billing_entity_id,
        subscription:,
        # A segment's product can have an optional legacy charge (including discarded charges).
        # TODO: Decide whether to assign that charge here; segment-backed fees currently receive nil.
        charge: selected_metered_item.billing_segment ? nil : selected_metered_item.charge,
        amount_cents: amount.amount_cents,
        precise_amount_cents: amount.precise_amount_cents,
        unit_amount_cents: amount.unit_amount_cents,
        precise_unit_amount: amount.precise_unit_amount,
        pricing_unit_usage: amount.pricing_unit_usage,
        amount_currency: selected_metered_item.currency,
        fee_type: selected_metered_item.fee_type,
        invoiceable: selected_metered_item.invoiceable,
        rate_card_rate: selected_metered_item.rate_card_rate,
        rate_override: selected_metered_item.rate_override,
        product_filter: selected_metered_item.product_filter,
        units:,
        total_aggregated_units: amount_result.total_aggregated_units || units,
        # TODO: Review which fee properties billing segments should expose.
        properties: selected_metered_item.billing_segment ? {} : selected_metered_item.filtered_for_charge_boundaries,
        events_count: amount_result.count,
        payment_status: :pending,
        taxes_amount_cents: 0,
        taxes_precise_amount_cents: 0.to_d,
        amount_details: amount_result.amount_details,
        grouped_by: amount_result.grouped_by || {},
        charge_filter: selected_metered_item.charge_filter&.persisted? ? selected_metered_item.charge_filter : nil
      )

      unless selected_metered_item.invoiceable?
        new_fee.pay_in_advance = selected_metered_item.pay_in_advance?
      end

      if !options.current_usage? && (adjusted = adjusted_fee(charge_filter: selected_metered_item.charge_filter, grouped_by: amount_result.grouped_by))&.adjusted_display_name?
        new_fee.invoice_display_name = adjusted.invoice_display_name
      end

      if options.apply_taxes
        taxes_result = Fees::ApplyTaxesService.call(fee: new_fee, plan:, customer:)
        taxes_result.raise_if_error!
      end

      new_fee
    end

    def should_persist_fee?(fee, fees)
      return true if options.recurring?
      return true if fee.units != 0 || fee.amount_cents != 0 || fee.events_count != 0
      return true if adjusted_fee(charge_filter: fee.charge_filter, grouped_by: fee.grouped_by).present?
      return true if fee.true_up_parent_fee.present?

      fees.any? { |f| f.true_up_parent_fee == fee }
    end

    def adjusted_fee(charge_filter:, grouped_by:)
      # TODO: Support adjusted product fees using contract and product/filter identity.
      # AdjustedFee currently depends on subscription_id and has no contract_id.
      return if metered_item.billing_segment
      return if options.skip_adjusted_fees
      @adjusted_fee ||= {}

      key = [
        charge_filter&.id,
        (grouped_by || {}).map do |k, v|
          "#{k}-#{v}"
        end.sort.join("|")
      ].compact.join("|")
      key = "default" if key.blank?

      return @adjusted_fee[key] if @adjusted_fee.key?(key)

      scope = AdjustedFee
        .where(invoice:, subscription_id: billing_context.subscription_id, charge: metered_item.charge, charge_filter:, fee_type: :charge)
        .where("(properties->>'charges_from_datetime')::timestamptz = ?", metered_item.boundaries.charges_from_datetime&.iso8601(3))
        .where("(properties->>'charges_to_datetime')::timestamptz = ?", metered_item.boundaries.charges_to_datetime&.iso8601(3))

      scope = if grouped_by.present?
        scope.where(grouped_by:)
      else
        scope.where(grouped_by: {})
      end

      @adjusted_fee[key] = scope.first
    end

    def init_true_up_fee
      fee = result.fees.find do |f|
        if metered_item.source.respond_to?(:product_filter)
          f.product_filter_id == metered_item.true_up_filter_id
        else
          f.charge_filter_id == metered_item.true_up_filter_id
        end
      end

      if metered_item.applied_pricing_unit
        used_amount_cents = result.fees.map(&:pricing_unit_usage).sum(&:amount_cents)
        used_precise_amount_cents = result.fees.map(&:pricing_unit_usage).sum(&:precise_amount_cents)
      else
        used_amount_cents = result.fees.sum(&:amount_cents)
        used_precise_amount_cents = result.fees.sum(&:precise_amount_cents)
      end

      # TODO: Refactor Fees::CreateTrueUpService to avoid passing the billing_segment down.
      true_up_fee = Fees::CreateTrueUpService.call(
        fee:, used_amount_cents:, used_precise_amount_cents:, billing_segment: metered_item.billing_segment
      ).true_up_fee
      result.fees << true_up_fee if true_up_fee
    end

    def apply_charge_model(aggregation_result:, selected_metered_item:)
      ChargeModels::Factory.new_instance(
        pricing_structure: selected_metered_item.pricing_structure,
        aggregation_result:,
        period_ratio: selected_metered_item.elapsed_period_ratio,
        calculate_projected_usage: options.calculate_projected_usage
      ).apply
    end

    def already_billed?
      # BillingSegment persistence is the source of truth for billing state.
      # TODO: Review this fee-level idempotency bypass once segment processing is finalized.
      return false if metered_item.billing_segment

      existing_fees = if invoice
        invoice.fees.where(charge_id: metered_item.charge.id, subscription_id: billing_context.subscription_id)
      else
        Fee.where(
          charge_id: metered_item.charge.id,
          subscription_id: billing_context.subscription_id,
          invoice_id: nil,
          pay_in_advance_event_id: nil
        ).where(
          "(properties->>'charges_from_datetime')::timestamptz = ?", metered_item.boundaries.charges_from_datetime&.iso8601(3)
        ).where(
          "(properties->>'charges_to_datetime')::timestamptz = ?", metered_item.boundaries.charges_to_datetime&.iso8601(3)
        )
      end

      return false if existing_fees.blank?

      result.fees = existing_fees
      true
    end

    def aggregator(selected_metered_item:)
      aggregate = true
      aggregate = filtered_aggregations.include?(selected_metered_item.filter_id) unless filtered_aggregations.nil?

      BillableMetrics::AggregationFactory.new_instance(
        metered_item: selected_metered_item,
        current_usage: options.current_usage?,
        billing_context:,
        boundaries: {
          from_datetime: selected_metered_item.boundaries.charges_from_datetime,
          to_datetime: selected_metered_item.boundaries.charges_to_datetime,
          charges_duration: selected_metered_item.boundaries.charges_duration,
          max_timestamp: selected_metered_item.boundaries.max_timestamp
        },
        filters: aggregation_filters(selected_metered_item:, bypass_aggregation: !aggregate),
        bypass_aggregation: !aggregate
      )
    end

    def persist_recurring_value(aggregation_results, selected_metered_item, breakdowns_by_group)
      # TODO: Review recurring product usage persistence. CachedAggregation needs
      # product_id and product_filter_id support before segment-backed values can be persisted.
      return if selected_metered_item.billing_segment
      return if options.current_usage?

      # NOTE: Only weighted sum and custom aggregations are setting this value
      return unless aggregation_results.first&.recurring_updated_at

      result.cached_aggregations ||= []

      # NOTE: persist current recurring value for next period
      aggregation_results.each do |aggregation_result|
        grouped_by = aggregation_result.grouped_by || {}

        result.cached_aggregations << CachedAggregation.find_or_initialize_by(
          organization_id: selected_metered_item.organization_id,
          external_subscription_id: billing_context.external_id,
          charge_id: selected_metered_item.charge.id,
          charge_filter_id: selected_metered_item.charge_filter&.id,
          grouped_by:,
          timestamp: aggregation_result.recurring_updated_at
        ) do |aggregation|
          aggregation.current_aggregation = aggregation_result.total_aggregated_units || aggregation_result.aggregation
          aggregation.current_amount = aggregation_result.custom_aggregation&.[](:amount)
          aggregation.presentation_breakdowns = breakdowns_by_group.fetch(grouped_by, [])
          aggregation.save!
        end
      end
    end

    def grouped_by_keys(selected_metered_item:)
      grouped_by_keys = selected_metered_item.pricing_group_keys
      grouped_by_keys if grouped_by_keys.present? && !options.usage_filters.skip_grouping
    end

    def aggregation_filters(selected_metered_item:, bypass_aggregation: false)
      # BaseStore reads charge_id; ClickhouseEnrichedStore uses it to select pre-enriched events.
      # Raw Postgres/ClickHouse aggregation uses metric code, billing context, and property filters instead.
      #
      # TODO: Support product_id in BaseStore and the enriched-event schema, enrichment, queries, and dedup keys.
      # Adding a product_id key here alone would be ignored. StoreFactory also needs a product-compatible path.
      # CachedAggregation reads in Aggregations::{BaseService, WeightedSumService, CustomService} obtain
      # charge_id from MeteredItem directly; those lookups and the cache schema also need product identity.
      filters = if selected_metered_item.billing_segment
        {}
      else
        {charge_id: selected_metered_item.charge.id}
      end

      grouped_by_keys = grouped_by_keys(selected_metered_item:)
      filters[:grouped_by] = grouped_by_keys if grouped_by_keys.present?

      presentation_group_keys_values = selected_metered_item.presentation_group_keys_values
      if presentation_group_keys_values.present?
        filters[:presentation_by] = presentation_group_keys_values & (options.usage_filters.filter_by_presentation || presentation_group_keys_values)
      end

      if selected_metered_item.billing_segment || selected_metered_item.charge_filter.present?
        if selected_metered_item.charge_filter
          # Aggregations::BaseService retains this object for charge_filter_id cache lookups;
          # WeightedSumService and CustomService also scope cached state by it. CustomService reads
          # its custom_properties, while BaseStore extracts its ID for enriched-event queries.
          #
          # TODO: Carry product_filter/selected_filter through aggregators, stores, enrichment, and cache
          # schemas/keys, preserving nil as the default bucket. Keep product custom_properties on the
          # segment's pricing snapshot; product event matching already uses matching/ignored_filters below.
          filters[:charge_filter] = selected_metered_item.charge_filter
        end

        # NOTE: Matching and ignored filters are only used to filter events when querying the store.
        #       When the aggregation is bypassed, no event is queried, so computing them is a waste
        #       (see BillableMetrics::Aggregations::BaseService#should_bypass_aggregation?).
        if !bypass_aggregation || selected_metered_item.billable_metric.recurring?
          matching_and_ignored_filters = selected_metered_item.matching_and_ignored_filters
          filters[:matching_filters] = matching_and_ignored_filters.matching_filters
          filters[:ignored_filters] = matching_and_ignored_filters.ignored_filters
        end
      end

      if options.usage_filters.filter_by_group.present?
        # when pricing group keys on a charge are "workspace" and "user", and filter_by_group is {"workspace" => ["A"]},
        # we want to remove the grouping keys "workspace", but keep the grouping key "user", so the usage will still be granular within the workspace
        options.usage_filters.filter_by_group.keys.each { |key| filters[:grouped_by]&.delete(key) }
        # NOTE: filters[:matching_filters] may come from ChargeFilter#to_h_with_all_values
        # which returns a frozen hash, so we must not mutate it in place.
        # expected matching_filters format is { "workspace" => ["A", "B"], "user" => ["U1", "U2"] }
        filters[:matching_filters] = (filters[:matching_filters] || {}).merge(options.usage_filters.filter_by_group)
      end

      filters
    end

    def validate!
      unless billing_context.is_a?(Billing::Context)
        raise ArgumentError, "billing_context must be a Billing::Context"
      end

      unless metered_item.is_a?(MeteredItem)
        raise ArgumentError, "metered_item must be a Fees::ChargeService::MeteredItem"
      end

      unless options.is_a?(Options)
        raise ArgumentError, "options must be a Fees::ChargeService::Options"
      end

      return unless options.apply_taxes

      unless plan
        raise ArgumentError, "plan is required when applying taxes"
      end

      unless customer
        raise ArgumentError, "customer is required when applying taxes"
      end
    end
  end
end
