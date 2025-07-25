# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class SumService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
        event_store.use_from_boundary = !billable_metric.recurring
      end

      def compute_aggregation(options: {})
        return empty_result if should_bypass_aggregation?

        aggregation = event_store.sum

        if options[:is_pay_in_advance] && options[:is_current_usage]
          handle_in_advance_current_usage(aggregation)
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result.count = event_store.count
        result.options = {running_total: running_total(options)}
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: "aggregation_failure", message: e.message)
      end

      # NOTE: Apply the grouped_by filter to the aggregation
      #       Result will have an aggregations attribute
      #       containing the aggregation result of each group.
      #
      #       This logic is only applicable for in arrears aggregation
      #       (exept for the current_usage update)
      #       as pay in advance aggregation will be computed on a single group
      #       with the grouped_by_values filter
      def compute_grouped_by_aggregation(options: {})
        return empty_results if should_bypass_aggregation?

        aggregations = event_store.grouped_sum
        return empty_results if aggregations.blank?

        counts = event_store.grouped_count

        result.aggregations = aggregations.map do |aggregation|
          group_result = BaseService::Result.new
          group_result.grouped_by = aggregation[:groups]

          aggregation_value = aggregation[:value]

          if options[:is_pay_in_advance] && options[:is_current_usage]
            handle_in_advance_current_usage(aggregation_value, target_result: group_result)
          else
            group_result.aggregation = aggregation_value
          end

          count = counts.find { |c| c[:groups] == aggregation[:groups] } || {}
          group_result.count = count[:value] || 0
          group_result.options = {running_total: running_total(options, grouped_by_values: group_result.grouped_by)}
          group_result
        end
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: "aggregation_failure", message: e.message)
      end

      def compute_precise_total_amount_cents(options: {})
        result.precise_total_amount_cents = event_store.sum_precise_total_amount_cents
        result.pay_in_advance_precise_total_amount_cents = event&.precise_total_amount_cents || 0
      end

      def compute_grouped_by_precise_total_amount_cents(options: {})
        aggregations = event_store.grouped_sum_precise_total_amount_cents
        return result if aggregations.blank?

        aggregations.each do |aggregation|
          group_result = result.aggregations.find { |group_result| group_result.grouped_by == aggregation[:groups] }
          next unless group_result

          group_result.precise_total_amount_cents = aggregation[:value]
        end
      end

      # NOTE: Return cumulative sum of field_name based on the number of free units
      #       (per_events or per_total_aggregation).
      def running_total(options, grouped_by_values: nil)
        free_units_per_events = options[:free_units_per_events].to_i
        free_units_per_total_aggregation = BigDecimal(options[:free_units_per_total_aggregation] || 0)

        return [] if free_units_per_events.zero? && free_units_per_total_aggregation.zero?

        event_store.with_grouped_by_values(grouped_by_values) do
          return running_total_per_events(free_units_per_events) unless free_units_per_events.zero?

          running_total_per_aggregation(free_units_per_total_aggregation)
        end
      end

      def running_total_per_events(limit)
        total = 0.0
        event_store.events_values(limit:).map { |x| total += x }
      end

      def running_total_per_aggregation(aggregation)
        total = 0.0
        event_store.events_values.each_with_object([]) do |val, accumulator|
          break accumulator if aggregation < total

          accumulator << total += val
        end
      end

      def compute_pay_in_advance_aggregation
        return BigDecimal(0) unless event
        return BigDecimal(0) if event.properties.blank?

        value = event.properties.fetch(billable_metric.field_name, 0).to_s

        cached_aggregation = find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: grouped_by_values
        )

        unless cached_aggregation
          return_value = BigDecimal(value).negative? ? "0" : value
          handle_event_metadata(current_aggregation: value, max_aggregation: value, units_applied: value)

          return BigDecimal(return_value)
        end

        current_aggregation = BigDecimal(cached_aggregation.current_aggregation) + BigDecimal(value)

        old_max = BigDecimal(cached_aggregation.max_aggregation)

        result = if current_aggregation > old_max
          diff = [current_aggregation, current_aggregation - old_max].max
          handle_event_metadata(current_aggregation:, max_aggregation: diff)

          current_aggregation - old_max
        else
          handle_event_metadata(current_aggregation:, max_aggregation: old_max, units_applied: value)

          0
        end

        BigDecimal(result)
      end

      def compute_per_event_aggregation(exclude_event:)
        event_store.events_values(force_from: true, exclude_event:)
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil, units_applied: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
        result.units_applied = units_applied unless units_applied.nil?
      end
    end
  end
end
