# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class UniqueCountService < BillableMetrics::Aggregations::BaseService
      def aggregate(from_datetime:, to_datetime:, options: {})
        @from_datetime = from_datetime
        @to_datetime = to_datetime

        result.aggregation = compute_aggregation.ceil(5)
        result.pay_in_advance_aggregation = BigDecimal(compute_pay_in_advance_aggregation)
        result.options = { running_total: running_total(options) }
        result.count = result.aggregation
        result
      end

      def compute_pay_in_advance_aggregation
        return 0 unless event
        return 0 if event.properties.blank?

        unless previous_event
          res = (operation_type == :add) ? 1 : 0
          handle_event_metadata(current_aggregation: res, max_aggregation: res)

          return res
        end

        old_aggregation = BigDecimal(previous_event.metadata['current_aggregation'])
        old_max = BigDecimal(previous_event.metadata['max_aggregation'])

        current_aggregation = (operation_type == :add) ? (old_aggregation + 1) : (old_aggregation - 1)

        if current_aggregation > old_max
          handle_event_metadata(current_aggregation:, max_aggregation: current_aggregation)

          1
        else
          handle_event_metadata(current_aggregation:, max_aggregation: old_max)

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

      private

      attr_reader :from_datetime, :to_datetime

      # This method fetches the latest event in current period. If such a event exists we know that metadata
      # with previous aggregation and previous maximum aggregation are stored there. Fetching these metadata values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def previous_event
        @previous_event ||= begin
          query = events_scope(from_datetime:, to_datetime:)
            .joins(:quantified_event)
            .where("#{sanitized_field_name} IS NOT NULL")
            .where.not(id: event.id)
            .where('quantified_events.added_at::timestamp(0) >= ?', from_datetime)
            .where('quantified_events.added_at::timestamp(0) <= ?', to_datetime)
            .order(created_at: :desc)

          query
            .where('quantified_events.removed_at::timestamp(0) IS NULL')
            .or(
              query
                .where('quantified_events.removed_at::timestamp(0) >= ?', from_datetime)
                .where('quantified_events.removed_at::timestamp(0) <= ?', to_datetime),
            )

          query.first
        end
      end

      def operation_type
        @operation_type ||= event.properties.fetch('operation_type', 'add')&.to_sym
      end

      def handle_event_metadata(current_aggregation: nil, max_aggregation: nil)
        result.current_aggregation = current_aggregation unless current_aggregation.nil?
        result.max_aggregation = max_aggregation unless max_aggregation.nil?
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
          .where(external_subscription_id: subscription.external_id)

        return quantified_events unless group

        quantified_events = quantified_events.where('properties @> ?', { group.key.to_s => group.value }.to_json)
        return quantified_events unless group.parent

        quantified_events.where('properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      def sanitized_operation_type
        ActiveRecord::Base.sanitize_sql_for_conditions(['events.properties->>operation_type'])
      end
    end
  end
end
