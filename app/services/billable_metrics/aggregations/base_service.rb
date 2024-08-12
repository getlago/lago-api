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
        @charge_filter = filters[:charge_filter]
        @event = filters[:event]
        @grouped_by = filters[:grouped_by]
        @grouped_by_values = filters[:grouped_by_values]

        @boundaries = boundaries

        result.aggregator = self
      end

      def aggregate(options: {})
        if grouped_by.present?
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

      def per_event_aggregation(exclude_event: false)
        Result.new.tap do |result|
          result.event_aggregation = compute_per_event_aggregation(exclude_event:)
        end
      end

      protected

      attr_accessor :event_store_class,
        :charge,
        :subscription,
        :filters,
        :charge_filter,
        :event,
        :boundaries,
        :grouped_by,
        :grouped_by_values

      delegate :billable_metric, to: :charge

      delegate :customer, to: :subscription

      def event_store
        @event_store ||= event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries:,
          filters:
        )
      end

      def from_datetime
        boundaries[:from_datetime]
      end

      def to_datetime
        boundaries[:to_datetime]
      end

      def handle_in_advance_current_usage(total_aggregation, target_result: result)
        cached_aggregation = find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: target_result.grouped_by
        )

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

      def empty_results
        empty_result = BaseService::Result.new
        empty_result.grouped_by = grouped_by.index_with { nil }
        empty_result.aggregation = 0
        empty_result.count = 0
        empty_result.current_usage_units = 0

        result.aggregations = [empty_result]
        result
      end

      # This method fetches the latest cached aggregation in current period. If such a record exists we know that
      # previous aggregation and previous maximum aggregation are stored there. Fetching these values
      # would help us in pay in advance value calculation without iterating through all events in current period
      def find_cached_aggregation(with_from_datetime:, with_to_datetime:, grouped_by: nil)
        query = CachedAggregation
          .where(organization_id: billable_metric.organization_id)
          .where(external_subscription_id: subscription.external_id)
          .where(charge_id: charge.id)
          .from_datetime(with_from_datetime)
          .to_datetime(with_to_datetime)
          .where(grouped_by: grouped_by.presence || {})
          .order(timestamp: :desc, created_at: :desc)

        query = query.where.not(event_transaction_id: event.transaction_id) if event.present?
        query = query.where(charge_filter_id: charge_filter.id) if charge_filter

        query.first
      end
    end
  end
end
