# frozen_string_literal: true

module Charges
  class PreviousChargesAndFiltersService < BaseService
    Result = BaseResult[:previous_charge_ids, :previous_charge_filter_ids]

    # Events::Stores::ClickhouseEnrichedStore relies on charge_ids and charge_filter_ids to filter
    # events for aggregations. For recurring billable metrics, and subscription upgrade/downgrade handling,
    # we need to fetch the previous charges and filters to build the aggregation query accordingly.
    def initialize(charge:, charge_filter:, subscription:)
      @charge = charge
      @charge_filter = charge_filter
      @subscription = subscription

      super
    end

    def call
      result.previous_charge_ids = []
      result.previous_charge_filter_ids = []

      return result unless applicable?

      visited = Set.new([subscription.id])
      current_subscription = subscription.previous_subscription

      while current_subscription
        break if visited.include?(current_subscription.id)

        visited << current_subscription.id

        previous_charges_scope = current_subscription.plan.charges

        if charge_filter.present?
          previous_charges_scope = previous_charges_scope.includes(filters: {values: :billable_metric_filter})
        end

        previous_charge = previous_charges_scope.find_by(billable_metric_id: charge.billable_metric_id)

        # TODO: how to deal with multiple charges for the same billable metric?
        if previous_charge
          result.previous_charge_ids << previous_charge.id

          if charge_filter.present?
            previous_filter = previous_charge.filters.find { |f| f.to_h.sort == charge_filter.to_h.sort }
            result.previous_charge_filter_ids << previous_filter.id if previous_filter
          end
        end

        current_subscription = current_subscription.previous_subscription
      end

      result
    end

    private

    attr_reader :charge, :charge_filter, :subscription

    def applicable?
      return false unless subscription.previous_subscription
      return false unless charge.billable_metric.recurring?
      return false unless subscription.organization.clickhouse_events_store?
      return false unless subscription.organization.feature_flag_enabled?(:enriched_events_aggregation)

      true
    end
  end
end
