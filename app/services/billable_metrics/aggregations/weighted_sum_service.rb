# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class WeightedSumService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def compute_aggregation(*)
        return empty_result if should_bypass_aggregation?

        weighted_result = event_store.weighted_sum(initial_value: period_initial_value)

        result.aggregation = weighted_result.value.ceil(20)
        result.count = weighted_result.events_count
        result.variation = weighted_result.variation
        result.total_aggregated_units = result.variation
        result.options = {}

        compute_breakdowns(billable_metric.recurring? ? latest_breakdowns : []) if presentation_by.present?

        if billable_metric.recurring?
          result.total_aggregated_units = latest_value + result.variation
          result.recurring_units = result.total_aggregated_units
          result.recurring_updated_at = event_store.last_event&.timestamp || from_datetime
          if result.breakdowns.blank?
            result.breakdowns = latest_breakdowns
            result.recurring_breakdowns = latest_breakdowns
          end
        end

        result
      end

      # NOTE: Apply the grouped_by filter to the aggregation
      #       Result will have an aggregations attribute
      #       containing the aggregation result of each group.
      def compute_grouped_by_aggregation(*)
        return empty_results if should_bypass_aggregation?

        aggregations = event_store.grouped_weighted_sum(initial_values: grouped_latest_values)
        if aggregations.blank?
          empty_results
          # No group carried over or in the period: the bucket closes at zero units
          result.aggregations.each { it.recurring_units = 0 } if billable_metric.recurring?
          return result
        end

        latest_values = []
        last_events = []
        if billable_metric.recurring?
          latest_values = grouped_latest_values
          last_events = event_store.grouped_last_event
        end

        if presentation_by.present?
          compute_breakdowns(billable_metric.recurring? ? grouped_latest_breakdowns : [])
          if result.breakdowns.empty?
            result.breakdowns = grouped_latest_breakdowns
            result.recurring_breakdowns = grouped_latest_breakdowns if billable_metric.recurring?
          end
        end

        result.aggregations = aggregations.map do |aggregation|
          group_result = BillableMetrics::Aggregations::BaseService::Result.new
          group_result.grouped_by = aggregation.groups

          group_result.aggregation = aggregation.value
          group_result.count = aggregation.events_count
          group_result.variation = aggregation.variation
          group_result.total_aggregated_units = group_result.variation

          if billable_metric.recurring?
            latest_value = latest_values.find { |c| c[:groups] == aggregation.groups }&.[](:value) || 0
            last_event = last_events.find { |c| c[:groups] == aggregation.groups }

            group_result.total_aggregated_units = latest_value + group_result.variation
            group_result.recurring_units = group_result.total_aggregated_units
            group_result.recurring_updated_at = last_event&.[](:timestamp) || from_datetime
          end

          group_result
        end

        result
      end

      private

      def compute_breakdowns(previous_breakdowns)
        initial_values = previous_breakdowns.map(&:with_indifferent_access)
        grouped_results = event_store.grouped_weighted_sum(uniq_grouped_by_and_presentation_by, initial_values:)

        result.breakdowns = grouped_results.map(&:to_grouped_hash)
        return unless billable_metric.recurring?

        # The fee shows the weighted units, the next period starts from the units active at period end
        result.recurring_breakdowns = grouped_results.map do |grouped_result|
          initial_value = initial_values.find { it[:groups] == grouped_result.groups }&.[](:value)
          {groups: grouped_result.groups, value: (initial_value || 0).to_d + grouped_result.variation}
        end
      end

      def period_initial_value
        return carryover_variations.fetch(nil, 0) if carryover_variations
        return 0 unless billable_metric.recurring?

        latest_value
      end

      def latest_value
        return @latest_value if defined?(@latest_value)

        if latest_snapshots
          return @latest_value = latest_snapshots.sum(BigDecimal(0), &:units) + unbilled_value
        end

        if latest_cached_aggregation
          return @latest_value = latest_cached_aggregation.current_aggregation + unbilled_value
        end

        if billing_context.previous_subscription_id?
          return @latest_value = latest_value_from_events.first
        end

        if cached_unbilled_since
          return @latest_value = unbilled_value
        end

        @latest_value = BigDecimal(0)
      end

      def latest_breakdowns
        return @latest_breakdowns if defined?(@latest_breakdowns)

        if latest_snapshots
          return @latest_breakdowns = with_unbilled(latest_snapshots.flat_map(&:presentation_breakdowns), unbilled_breakdowns)
        end

        if latest_cached_aggregation
          return @latest_breakdowns = with_unbilled(latest_cached_aggregation.presentation_breakdowns, unbilled_breakdowns)
        end

        if billing_context.previous_subscription_id?
          return @latest_breakdowns = latest_value_from_events.second
        end

        if cached_unbilled_since
          return @latest_breakdowns = unbilled_breakdowns
        end

        @latest_breakdowns = []
      end

      # Not a period closing after this one starts (previous subscription terminated on upgrade): the variation
      # reads its events again. Nor an older one that an invoice closed since, or the previous subscription's,
      # whose cached aggregation holds the level. Without snapshots, the period still tells that the bucket had
      # no active units.
      def latest_snapshots
        return @latest_snapshots if defined?(@latest_snapshots)
        return @latest_snapshots = nil unless initial_period

        readable = initial_period.weighted_sum_start?(from_datetime) { last_billed_charges_to_datetime }
        @latest_snapshots = initial_value if readable
      end

      # The latest value closes a billed period. Periods closed since then but not invoiced yet (the minutes
      # before the billing run) add the events dated in them, as their invoice will.
      def unbilled_store
        return @unbilled_store if defined?(@unbilled_store)

        closed_at = latest_snapshots ? unbilled_since(initial_period.to_datetime) : cached_unbilled_since
        return @unbilled_store = nil unless closed_at

        # The stores floor from_datetime to the millisecond
        @unbilled_store = event_store.for_window(from_datetime: closed_at + 0.001.seconds, to_datetime: previous_period_end)
      end

      def unbilled_since(closed_at)
        closed_at if closed_at && closed_at < from_datetime - 1.second
      end

      def cached_unbilled_since
        grouped_by.present? ? grouped_latest_cached_aggregations : latest_cached_aggregation
        @cached_unbilled_since
      end

      # Rows written after the last invoiced period come from progressive billing invoices: the unbilled
      # events would count their events again, so the rows of the last invoiced period are read instead.
      # Without any, the level starts from zero at that period, as its invoice found no row either, unless a
      # plan change reads the history of the external id.
      def billed_cached_rows(query)
        rows = yield(query)
        @cached_unbilled_since = cached_rows_unbilled_since(rows)
        return rows unless @cached_unbilled_since && rows.any? { it.timestamp > @cached_unbilled_since }

        yield(query.where(timestamp: ..@cached_unbilled_since))
      end

      # A row written after this period started comes from the invoice of the previous period: none is left
      # unbilled, and the invoices query is skipped on every usage refresh but those before that invoice.
      def cached_rows_unbilled_since(rows)
        return if rows.empty? || rows.any? { it.created_at >= from_datetime }

        unbilled_since(last_billed_charges_to_datetime)
      end

      def last_billed_charges_to_datetime
        billing_context.last_billed_charges_to_datetime(before: from_datetime)
      end

      def unbilled_value
        return BigDecimal(0) unless unbilled_store

        BigDecimal(unbilled_store.sum(with_count: false).value.to_s)
      end

      def unbilled_grouped_values
        return [] unless unbilled_store

        unbilled_store.grouped_sum(with_count: false).map(&:to_grouped_hash)
      end

      def unbilled_breakdowns
        return [] unless unbilled_store && presentation_by.present?

        unbilled_store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash)
      end

      def with_unbilled(values, unbilled)
        return values if unbilled.empty?

        (values.map(&:with_indifferent_access) + unbilled).group_by { it[:groups].to_h.stringify_keys }.map do |groups, items|
          {groups:, value: items.sum(BigDecimal(0)) { BigDecimal(it[:value].to_s) }}
        end
      end

      def latest_cached_aggregation
        return @latest_cached_aggregation if defined?(@latest_cached_aggregation)

        query = latest_cached_aggregations.where(grouped_by: grouped_by.presence || {})
        @latest_cached_aggregation = billed_cached_rows(query) { Array(it.first) }.first
      end

      def latest_cached_aggregations
        return @latest_cached_aggregations if defined?(@latest_cached_aggregations)

        query = CachedAggregation
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: billing_context.external_id)
          .where(metered_item.cached_aggregation_identity)
          .where(timestamp: ...from_datetime)
          .order(timestamp: :desc, created_at: :desc)

        query = query.where(charge_filter_id: charge_filter.id) if charge_filter

        @latest_cached_aggregations = query
      end

      # NOTE: In case of upgrade/downgrade, if latest value is not persisted yet,
      #       we need to fetch latest value from previous events attached to the same external subscription ID
      def latest_value_from_events
        return @latest_value_from_events if defined?(@latest_value_from_events)

        store = event_store.for_window(to_datetime: previous_period_end)
        store.use_from_boundary = false

        breakdowns = presentation_by.present? ? store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash) : []

        @latest_value_from_events = [BigDecimal(store.sum(with_count: false).value), breakdowns]
      end

      def grouped_latest_values
        return carryover_variations.map { |groups, value| {groups:, value:} } if carryover_variations
        return @grouped_latest_values if defined?(@grouped_latest_values)

        if latest_snapshots
          return @grouped_latest_values = with_unbilled(
            latest_snapshots.map { {groups: it.grouped_by, value: it.units} }, unbilled_grouped_values
          )
        end

        if grouped_latest_cached_aggregations.any?
          return @grouped_latest_values = with_unbilled(
            grouped_latest_cached_aggregations.map { {groups: it.grouped_by, value: it.current_aggregation} },
            unbilled_grouped_values
          )
        end

        if billing_context.previous_subscription_id?
          return @grouped_latest_values = grouped_latest_values_from_events.first
        end

        if cached_unbilled_since
          return @grouped_latest_values = unbilled_grouped_values
        end

        @grouped_latest_values = {}
      end

      def grouped_latest_breakdowns
        return @grouped_latest_breakdowns if defined?(@grouped_latest_breakdowns)

        if latest_snapshots
          breakdowns = latest_snapshots.flat_map { with_grouped_by_keys(it.grouped_by, it.presentation_breakdowns) }
          return @grouped_latest_breakdowns = with_unbilled(breakdowns, unbilled_breakdowns)
        end

        if grouped_latest_cached_aggregations.any?
          breakdowns = grouped_latest_cached_aggregations.flat_map { with_grouped_by_keys(it.grouped_by, it.presentation_breakdowns) }
          return @grouped_latest_breakdowns = with_unbilled(breakdowns, unbilled_breakdowns)
        end

        if billing_context.previous_subscription_id?
          return @grouped_latest_breakdowns = grouped_latest_values_from_events.second
        end

        if cached_unbilled_since
          return @grouped_latest_breakdowns = unbilled_breakdowns
        end

        @grouped_latest_breakdowns = []
      end

      # Fees::ChargeService stores the breakdowns without the grouped_by keys of their group
      def with_grouped_by_keys(grouped_by, breakdowns)
        breakdowns.map do |breakdown|
          breakdown = breakdown.with_indifferent_access
          {groups: grouped_by.merge(breakdown[:groups]), value: breakdown[:value]}
        end
      end

      def grouped_latest_cached_aggregations
        return @grouped_latest_cached_aggregations if defined?(@grouped_latest_cached_aggregations)

        query = latest_cached_aggregations

        grouped_by.each do |key|
          query = query.where("grouped_by?:key", key:)
        end

        @grouped_latest_cached_aggregations = billed_cached_rows(query) { it.to_a.uniq(&:grouped_by) }
      end

      def previous_period_end
        precision = if event_store.is_a?(Events::Stores::ClickhouseStore)
          0.001.seconds
        else
          0.000001.seconds
        end

        from_datetime - precision
      end

      def grouped_latest_values_from_events
        store = event_store.for_window(to_datetime: previous_period_end)
        store.use_from_boundary = false

        breakdowns = presentation_by.present? ? store.grouped_sum(uniq_grouped_by_and_presentation_by, with_count: false).map(&:to_grouped_hash) : []

        [store.grouped_sum(with_count: false).map(&:to_grouped_hash), breakdowns]
      end
    end
  end
end
