# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class SumService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_datetime:, to_datetime:, options: {})
        @from_datetime = from_datetime
        @to_datetime = to_datetime

        if options[:is_pay_in_advance] && options[:is_current_usage]
          result.aggregation = BigDecimal(previous_event ? previous_event.metadata['max_aggregation'] : 0)
          result.current_usage_units = BigDecimal(previous_event ? previous_event.metadata['current_aggregation'] : 0)
        else
          result.aggregation = events.sum("(#{sanitized_field_name})::numeric")
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

        unless previous_event
          value = event.properties.fetch(billable_metric.field_name, 0).to_s
          handle_event_metadata(current_aggregation: value, max_aggregation: value)

          return BigDecimal(value)
        end

        current_aggregation = BigDecimal(previous_event.metadata['current_aggregation']) +
                              BigDecimal(event.properties.fetch(billable_metric.field_name, 0).to_s)

        old_max = BigDecimal(previous_event.metadata['max_aggregation'])

        result = if current_aggregation > old_max
          handle_event_metadata(current_aggregation:, max_aggregation: current_aggregation)

          current_aggregation - old_max
        else
          handle_event_metadata(current_aggregation:, max_aggregation: old_max)

          0
        end

        BigDecimal(result)
      end

      private

      attr_reader :from_datetime, :to_datetime

      def events
        @events ||= begin
          charges_from_date = billable_metric.recurring? ? subscription.started_at : from_datetime

          events_scope(from_datetime: charges_from_date, to_datetime:).where("#{sanitized_field_name} IS NOT NULL")
        end
      end

      # This method fetches the latest event in current period. If such a event exists we know that metadata
      # with previous aggregation and previous maximum aggregation are stored there. Fetching these metadata values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def previous_event
        @previous_event ||= begin
          scope = events_scope(from_datetime:, to_datetime:).where("#{sanitized_field_name} IS NOT NULL")

          scope = scope.where.not(id: event.id) if event.present?

          scope.order(created_at: :desc).first
        end
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
      end
    end
  end
end
