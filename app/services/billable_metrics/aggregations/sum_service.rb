# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class SumService < BillableMetrics::Aggregations::BaseService
      def initialize(...)
        super(...)

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
        event_store.use_from_boundary = !billable_metric.recurring
      end

      def compute_aggregation(options: {})
        aggregation = event_store.sum

        if options[:is_pay_in_advance] && options[:is_current_usage]
          handle_in_advance_current_usage(aggregation)
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result.count = event_store.count
        result.options = { running_total: running_total(options) }
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
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
          group_result
        end

        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      # NOTE: Return cumulative sum of field_name based on the number of free units (per_events or per_total_aggregation).
      def running_total(options)
        free_units_per_events = options[:free_units_per_events].to_i
        free_units_per_total_aggregation = BigDecimal(options[:free_units_per_total_aggregation] || 0)

        return [] if free_units_per_events.zero? && free_units_per_total_aggregation.zero?
        return running_total_per_events(free_units_per_events) unless free_units_per_events.zero?

        running_total_per_aggregation(free_units_per_total_aggregation)
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

        cached_aggregation = find_cached_aggregation

        unless cached_aggregation
          return_value = BigDecimal(value).negative? ? '0' : value
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

      def compute_per_event_aggregation
        event_store.events_values(force_from: true)
      end

      def support_grouped_aggregation?
        true
      end

      # This method fetches the latest cached aggregation in current period. If such a record exists we know that
      # previous aggregation and previous maximum aggregation are stored there. Fetching these values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def find_cached_aggregation(with_from_datetime: from_datetime, with_to_datetime: to_datetime, grouped_by: nil)
        query = CachedAggregation
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)
          .where(charge_id: charge.id)
          .from_datetime(with_from_datetime)
          .to_datetime(with_to_datetime)
          .order(timestamp: :desc)

        if grouped_by.present?
          grouped_by.each do |key, value|
            query = query.where('cached_aggregations.grouped_by @> ?', { key.to_s => value.to_s }.to_json)
          end
        end

        query = query.where.not(event_id: event.id) if event.present?
        query = query.where(group_id: group.id) if group

        query.first
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil, units_applied: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
        result.units_applied = units_applied unless units_applied.nil?
      end
    end
  end
end
