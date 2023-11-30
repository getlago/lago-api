# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class SumService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        aggregation = events.sum("(#{sanitized_field_name})::numeric")

        if options[:is_pay_in_advance] && options[:is_current_usage]
          handle_in_advance_current_usage(aggregation)
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result.count = events.count
        result.options = { running_total: running_total(events, options) }
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      # NOTE: Return cumulative sum of field_name based on the number of free units (per_events or per_total_aggregation).
      def running_total(events, options)
        free_units_per_events = options[:free_units_per_events].to_i
        free_units_per_total_aggregation = BigDecimal(options[:free_units_per_total_aggregation] || 0)

        return [] if free_units_per_events.zero? && free_units_per_total_aggregation.zero?

        events = events.order(created_at: :asc)
        return running_total_per_events(events, free_units_per_events) unless free_units_per_events.zero?

        running_total_per_aggregation(events, free_units_per_total_aggregation)
      end

      def running_total_per_events(events, limit)
        total = 0.0

        events
          .limit(limit)
          .pluck(Arel.sql("(#{sanitized_field_name})::numeric"))
          .map { |x| total += x }
      end

      def running_total_per_aggregation(events, aggregation)
        total = 0.0

        events
          .pluck(Arel.sql("(#{sanitized_field_name})::numeric"))
          .each_with_object([]) do |val, accumulator|
            break accumulator if aggregation < total

            accumulator << total += val
          end
      end

      def compute_pay_in_advance_aggregation
        return BigDecimal(0) unless event
        return BigDecimal(0) if event.properties.blank?

        value = event.properties.fetch(billable_metric.field_name, 0).to_s

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
        events_scope(from_datetime:, to_datetime:).pluck(Arel.sql("COALESCE((#{sanitized_field_name})::numeric, 0)"))
      end

      protected

      def events
        @events ||= begin
          query = if billable_metric.recurring?
            recurring_events_scope(to_datetime:)
          else
            events_scope(from_datetime:, to_datetime:)
          end

          query.where(field_presence_condition)
            .where(field_numeric_condition)
        end
      end

      # This method fetches the latest cached aggregation in current period. If such a record exists we know that
      # previous aggregation and previous maximum aggregation are stored there. Fetching these values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def cached_aggregation
        return @cached_aggregation if @cached_aggregation

        query = CachedAggregation
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)
          .where(charge_id: charge.id)
          .from_datetime(from_datetime)
          .to_datetime(to_datetime)
          .order(timestamp: :desc)

        query = query.where.not(event_id: event.id) if event.present?
        query = query.where(group_id: group.id) if group

        @cached_aggregation = query.first
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil, units_applied: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
        result.units_applied = units_applied unless units_applied.nil?
      end
    end
  end
end
