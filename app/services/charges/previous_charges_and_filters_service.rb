# frozen_string_literal: true

module Charges
  class PreviousChargesAndFiltersService < BaseService
    Result = BaseResult[:previous_charge_ids, :previous_charge_filters]

    # Events::Stores::ClickhouseEnrichedStore relies on charge_ids and charge_filter_ids to filter
    # events for aggregations. For recurring billable metrics, and subscription upgrade/downgrade handling,
    # we need to fetch the previous charges and filters to build the aggregation query accordingly.
    def initialize(charge:, subscription:)
      @charge = charge
      @subscription = subscription

      super
    end

    def call
      result.previous_charge_ids = []
      result.previous_charge_filters = {}
      return result unless applicable?

      current_charge_filters = charge.filters.includes(values: :billable_metric_filter)
      current_filter_hashes = current_charge_filters.map { |filter| [filter.id, filter.to_h.sort] }.to_h

      visited = Set.new([subscription.id])
      current_subscription = subscription.previous_subscription

      while current_subscription
        break if visited.include?(current_subscription.id)

        visited << current_subscription.id

        previous_charge = current_subscription.plan.charges
          .includes(filters: {values: :billable_metric_filter})
          .find_by(billable_metric_id: charge.billable_metric_id)

        # TODO: how to deal with multiple charges for the same billable metric?
        if previous_charge
          result.previous_charge_ids << previous_charge.id

          current_filter_hashes.each do |filter_id, filter_hash|
            previous_filter = previous_charge.filters.find { it.to_h.sort == filter_hash }
            if previous_filter
              result.previous_charge_filters[filter_id] ||= []
              result.previous_charge_filters[filter_id] << previous_filter.id
            end
          end
        end

        current_subscription = current_subscription.previous_subscription
      end

      result
    end

    private

    attr_reader :charge, :subscription

    def applicable?
      return false unless Events::Stores::StoreFactory.supports_clickhouse?
      return false unless subscription.previous_subscription
      return false unless charge.billable_metric.recurring?
      return false unless subscription.organization.clickhouse_events_store?
      return false unless subscription.organization.feature_flag_enabled?(:enriched_events_aggregation)

      true
    end
  end
end
