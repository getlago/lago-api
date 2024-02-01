# frozen_string_literal: true

module BillableMetrics
  module Aggregations
    class BaseService < ::BaseService
      def initialize(event_store_class:, charge:, subscription:, boundaries:, filters: {})
        super(nil)
        @event_store_class = event_store_class
        @charge = charge
        @subscription = subscription

        @filters = filters
        @group = filters[:group]
        @event = filters[:event]
        @grouped_by = filters[:grouped_by]

        @boundaries = boundaries

        result.aggregator = self
      end

      def aggregate(options: {})
        if grouped_by.present? && support_grouped_aggregation?
          compute_grouped_by_aggregation(options:)
        else
          compute_aggregation(options:)
        end
      end

      def compute_aggregation(options: {})
        raise NotImplementedError
      end

      def compute_grouped_by_aggregation(options: {})
        raise NotImplementedError
      end

      def per_event_aggregation
        Result.new.tap do |result|
          result.event_aggregation = compute_per_event_aggregation
        end
      end

      protected

      attr_accessor :event_store_class, :charge, :subscription, :filters, :group, :event, :boundaries, :grouped_by

      delegate :billable_metric, to: :charge

      delegate :customer, to: :subscription

      def event_store
        @event_store ||= event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries:,
          filters:,
        )
      end

      def from_datetime
        boundaries[:from_datetime]
      end

      def to_datetime
        boundaries[:to_datetime]
      end

      def count_unique_group_scope(events)
        events = events.where('quantified_events.properties @> ?', { group.key.to_s => group.value }.to_json)
        return events unless group.parent

        events.where('quantified_events.properties @> ?', { group.parent.key.to_s => group.parent.value }.to_json)
      end

      def handle_in_advance_current_usage(total_aggregation, target_result: result)
        cached_aggregation = find_cached_aggregation(grouped_by: target_result.grouped_by)

        if cached_aggregation
          aggregation = total_aggregation -
                        BigDecimal(cached_aggregation.current_aggregation) +
                        BigDecimal(cached_aggregation.max_aggregation)

          target_result.aggregation = aggregation
        else
          target_result.aggregation = total_aggregation
        end

        target_result.current_usage_units = total_aggregation

        target_result.aggregation = 0 if target_result.aggregation.negative?
        target_result.current_usage_units = 0 if target_result.current_usage_units.negative?
      end

      def support_grouped_aggregation?
        false
      end

      def empty_results
        empty_result = BaseService::Result.new
        empty_result.grouped_by = grouped_by.index_with { nil }
        empty_result.aggregation = 0
        empty_result.count = 0
        empty_result.current_usage_units = 0

        result.aggregations = [empty_result]
        result
      end
    end
  end
end
