# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(options: {})
        aggregation = compute_aggregation.ceil(5)

        if options[:is_pay_in_advance] && options[:is_current_usage]
          handle_in_advance_current_usage(aggregation)
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = BigDecimal(compute_pay_in_advance_aggregation)
        result.options = { running_total: running_total(options) }
        result.count = result.aggregation
        result
      end

      def compute_pay_in_advance_aggregation
        return 0 unless event
        return 0 if event.properties.blank?

        newly_applied_units = (operation_type == :add) ? 1 : 0

        unless previous_event
          handle_event_metadata(
            current_aggregation: newly_applied_units,
            max_aggregation: newly_applied_units,
            units_applied: newly_applied_units,
          )

          return newly_applied_units
        end

        old_aggregation = BigDecimal(previous_event.metadata['current_aggregation'])
        old_max = BigDecimal(previous_event.metadata['max_aggregation'])

        current_aggregation = (operation_type == :add) ? (old_aggregation + 1) : (old_aggregation - 1)

        if current_aggregation > old_max
          handle_event_metadata(current_aggregation:, max_aggregation: current_aggregation)

          1
        else
          handle_event_metadata(current_aggregation:, max_aggregation: old_max, units_applied: newly_applied_units)

          0
        end
      end

      # NOTE: Return cumulative sum of event count based on the number of free units
      #       (per_events or per_total_aggregation).
      def running_total(options)
        free_units_per_events = options[:free_units_per_events].to_i
        free_units_per_total_aggregation = BigDecimal(options[:free_units_per_total_aggregation] || 0)

        return [] if free_units_per_events.zero? && free_units_per_total_aggregation.zero?

        (1..result.aggregation).to_a
      end

      def compute_per_event_aggregation
        (0...added_query.count).map { |_| 1 }
      end

      protected

      # This method fetches the latest event in current period. If such a event exists we know that metadata
      # with previous aggregation and previous maximum aggregation are stored there. Fetching these metadata values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def previous_event
        @previous_event ||= begin
          query = if billable_metric.recurring?
            recurring_events_scope(to_datetime:, from_datetime:)
          else
            events_scope(from_datetime:, to_datetime:)
          end
          query = query
            .joins(:quantified_event)
            .where("#{sanitized_field_name} IS NOT NULL")
            .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
            .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)

          query = query.where.not(id: event.id) if event.present?
          query = query.reorder(created_at: :desc)

          query
            .where('quantified_events.removed_at::timestamp(0) IS NULL')
            .or(
              query
                .where('quantified_events.removed_at::timestamp(0) >= ?', from_datetime)
                .where('quantified_events.removed_at::timestamp(0) <= ?', to_datetime),
            )
            .first
        end
      end

      def operation_type
        @operation_type ||= event.properties.fetch('operation_type', 'add')&.to_sym
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil, units_applied: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
        result.units_applied = units_applied unless units_applied.nil?
      end

      def compute_aggregation
        ActiveRecord::Base.connection.execute(aggregation_query).first['aggregation_result']
      end

      def aggregation_query
        queries = [
          # NOTE: Billed on the full period. We will replace 1::numeric with proration_coefficient::numeric
          # in the next part
          persisted_query.select('SUM(1::numeric)').to_sql,

          # NOTE: Added during the period, We will replace 1::numeric with proration_coefficient::numeric
          # in the next part
          added_query.select('SUM(1::numeric)').to_sql,
        ]

        "SELECT (#{queries.map { |q| "COALESCE((#{q}), 0)" }.join(' + ')}) AS aggregation_result"
      end

      def persisted_query
        return QuantifiedEvent.none unless billable_metric.recurring?

        base_scope
          .where('quantified_events.added_at::timestamp(0) < ?', from_datetime)
          .where('quantified_events.removed_at IS NULL OR quantified_events.removed_at::timestamp(0) > ?', to_datetime)
      end

      def added_query
        base_scope
          .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
          .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)
          .where('quantified_events.removed_at::timestamp(0) IS NULL OR quantified_events.removed_at > ?', to_datetime)
      end

      def base_scope
        quantified_events = QuantifiedEvent
          .joins(customer: :organization)
          .where(billable_metric_id: billable_metric.id)
          .where(customer_id: subscription.customer_id)

        quantified_events = if billable_metric.recurring?
          quantified_events.where(external_subscription_id: subscription.external_id)
        else
          quantified_events.joins(:events).where(events: { subscription_id: subscription.id })
        end

        return quantified_events unless group

        count_unique_group_scope(quantified_events)
      end

      def sanitized_operation_type
        ActiveRecord::Base.sanitize_sql_for_conditions(['events.properties->>operation_type'])
      end
    end
  end
end
