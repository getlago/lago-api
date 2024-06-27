# frozen_string_literal: true

class Charge
  attribute :invoicing_strategy, :integer, default: nil
end

class RefreshCachedAggregations < ActiveRecord::Migration[7.0]
  def change
    # NOTE: All subscriptions having a recurring weighted sum metric in the plan
    #       that started before the QuantifiedEvent migration
    #       aS the first billing period is not impacted
    subscriptions = Subscription
      .joins(plan: {charges: :billable_metric})
      .includes(plan: {charges: :billable_metric})
      .merge(BillableMetric.weighted_sum_agg.where(recurring: true))
      .where(started_at: ...Time.zone.parse('2024-05-23'))

    subscriptions.find_each do |subscription|
      # NOTE: All recurring weighted sum charges
      charges = subscription.plan.charges.select { |c| c.billable_metric.recurring? && c.billable_metric.weighted_sum_agg? }

      charges.each do |charge|
        # NOTE: All fees for the charge created after the QuantifiedEvent migration
        fees = charge.fees
          .includes(:charge_filter)
          .where(created_at: Time.zone.parse('2024-05-23')...)

        fees.find_each do |fee|
          filters = {}
          # NOTE: Take charge filters and default charge filter into account
          charge_filter = if charge.billable_metric.filters.any?
            fee.charge_filter || ChargeFilter.new(charge:)
          end

          properties = charge_filter&.properties || charge.properties
          filters[:grouped_by] = properties['grouped_by'] if charge.standard? && properties['grouped_by'].present?
          if charge_filter.present?
            result = ChargeFilters::MatchingAndIgnoredService.call(charge:, filter: charge_filter)
            filters[:charge_filter] = charge_filter
            filters[:matching_filters] = result.matching_filters
            filters[:ignored_filters] = result.ignored_filters
          end

          # NOTE: Recompute the aggregation
          aggregation_results = BillableMetrics::AggregationFactory.new_instance(
            charge:,
            current_usage: false,
            subscription:,
            boundaries: {
              from_datetime: Time.zone.parse(fee.properties["charges_from_datetime"]),
              to_datetime: Time.zone.parse(fee.properties["charges_to_datetime"]),
              charges_duration: fee.properties["charges_duration"]
            },
            filters:
          ).aggregate(options: {})

          aggregation_results.aggregations || [aggregation_results].each do |aggregation_result|
            cached_aggregation = CachedAggregation.find_by(
              organization_id: subscription.organization.id,
              external_subscription_id: subscription.external_id,
              charge_id: charge.id,
              charge_filter_id: charge_filter&.id,
              grouped_by: aggregation_result.grouped_by || {},
              timestamp: aggregation_result.recurring_updated_at
            )

            # NOTE: Update the cached value for the last billing period
            #       This will ensure that next invoice will use the right initial value
            cached_aggregation&.update!(current_aggregation: aggregation_result.total_aggregated_units || aggregation_result.aggregation)
          end
        end
      end
    end
  end
end
