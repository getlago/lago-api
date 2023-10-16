# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class BaseService < ::BaseService
      def initialize(event_store_class:, charge:, subscription:, boundaries:, group: nil, event: nil) # rubocop:disable Metrics/ParameterLists
        super(nil)
        @event_store_class = event_store_class
        @charge = charge
        @subscription = subscription
        @group = group
        @event = event
        @boundaries = boundaries

        result.aggregator = self
      end

      def aggregate(options: {})
        raise(NotImplementedError)
      end

      def per_event_aggregation
        Result.new.tap do |result|
          result.event_aggregation = compute_per_event_aggregation
        end
      end

      protected

      attr_accessor :event_store_class, :charge, :subscription, :group, :event, :boundaries

      delegate :billable_metric, to: :charge

      delegate :customer, to: :subscription

      def event_store
        @event_store ||= event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries:,
          group:,
          event:,
        )
      end

      def from_datetime
        boundaries[:from_datetime]
      end

      def to_datetime
        boundaries[:to_datetime]
      end

      def events_scope(from_datetime:, to_datetime:)
        events = Event.where(external_subscription_id: subscription.external_id)
          .from_datetime(from_datetime)
          .to_datetime(to_datetime)
          .where(code: billable_metric.code)
          .order(timestamp: :asc)
        return events unless group

        group_scope(events)
      end

      def recurring_events_scope(to_datetime:, from_datetime: nil)
        events = Event.where(external_subscription_id: subscription.external_id)
          .where(code: billable_metric.code)
          .to_datetime(to_datetime)
        events = events.from_datetime(from_datetime) unless from_datetime.nil?
        return events unless group

        group_scope(events)
      end

      def group_scope(events)
        events = events.where('events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return events unless group.parent

        events.where('events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      def count_unique_group_scope(events)
        events = events.where('quantified_events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return events unless group.parent

        events.where('quantified_events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      def sanitized_name(property)
        ActiveRecord::Base.sanitize_sql_for_conditions(
          ['events.properties->>?', property],
        )
      end

      def sanitized_field_name
        sanitized_name(billable_metric.field_name)
      end

      def field_presence_condition
        "events.properties::jsonb ? '#{ActiveRecord::Base.sanitize_sql_for_conditions(billable_metric.field_name)}'"
      end

      def field_numeric_condition
        # NOTE: ensure property value is a numeric value
        "#{sanitized_field_name} ~ '^-?\\d+(\\.\\d+)?$'"
      end

      def handle_in_advance_current_usage(total_aggregation)
        if cached_aggregation
          aggregation = total_aggregation -
                        BigDecimal(cached_aggregation.current_aggregation) +
                        BigDecimal(cached_aggregation.max_aggregation)

          result.aggregation = aggregation
        else
          result.aggregation = total_aggregation
        end

        result.current_usage_units = total_aggregation

        result.aggregation = 0 if result.aggregation.negative?
        result.current_usage_units = 0 if result.current_usage_units.negative?
      end

      def get_cached_aggregation_in_interval(from_datetime:, to_datetime:)
        @from_datetime = from_datetime
        @to_datetime = to_datetime

        cached_aggregation
      end
    end
  end
end
