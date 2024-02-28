# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class BaseService < BillableMetrics::Aggregations::BaseService
      def compute_pay_in_advance_aggregation(aggregation_without_proration:)
        return BigDecimal(0) unless event
        return BigDecimal(0) if event.properties.blank?

        result_without_proration = aggregation_without_proration.pay_in_advance_aggregation
        result.full_units_number = result_without_proration
        result.units_applied = aggregation_without_proration.units_applied

        # In order to get proration coefficient we have to divide number of seconds with number
        # of seconds in one day (86400). That way we will get number of days when the service was used.
        proration_coefficient = Utils::DatetimeService.date_diff_with_timezone(
          event.timestamp,
          to_datetime,
          customer.applicable_timezone,
        ).fdiv(period_duration)

        value = (result_without_proration * proration_coefficient).ceil(5)

        extend_cached_aggregation(value, aggregation_without_proration)

        value
      end

      # We need to extend cached aggregation with max_aggregation_with_proration. This attribute will be used
      # for current usage in pay_in_advance case
      def extend_cached_aggregation(prorated_value, aggregation_without_proration)
        result.max_aggregation = aggregation_without_proration.max_aggregation
        result.current_aggregation = aggregation_without_proration.current_aggregation

        cached_aggregation = base_aggregator.find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: grouped_by_values,
        )

        unless cached_aggregation
          result.max_aggregation_with_proration = prorated_value.to_s

          return
        end

        result.max_aggregation_with_proration = begin
          if BigDecimal(aggregation_without_proration.max_aggregation) > BigDecimal(cached_aggregation.max_aggregation)
            BigDecimal(cached_aggregation.max_aggregation_with_proration) + prorated_value
          else
            BigDecimal(cached_aggregation.max_aggregation_with_proration)
          end
        end
      end

      # In current usage section two main values are presented, number of units in period and amount.
      # Proration affects only amount (calculated from aggregation) and number of units shows full number of units
      # (calculated from current_usage_units).
      def handle_current_usage(result_with_proration, is_pay_in_advance, aggregation_without_proration:, target_result:)
        value_without_proration = aggregation_without_proration.aggregation
        cached_aggregation = base_aggregator.find_cached_aggregation(
          with_from_datetime: from_datetime,
          with_to_datetime: to_datetime,
          grouped_by: target_result.grouped_by,
        )

        if !is_pay_in_advance
          target_result.aggregation = result_with_proration.negative? ? 0 : result_with_proration
          target_result.current_usage_units = value_without_proration.negative? ? 0 : value_without_proration
        elsif cached_aggregation && persisted_pro_rata < 1
          target_result.current_usage_units = aggregation_without_proration.current_usage_units

          persisted_units_without_proration = aggregation_without_proration.current_usage_units -
                                              BigDecimal(cached_aggregation.current_aggregation)
          target_result.aggregation = (persisted_units_without_proration * persisted_pro_rata).ceil(5) +
                                      BigDecimal(cached_aggregation.max_aggregation_with_proration)
        elsif cached_aggregation
          target_result.current_usage_units = aggregation_without_proration.current_usage_units
          target_result.aggregation = aggregation_without_proration.current_usage_units -
                                      BigDecimal(cached_aggregation.current_aggregation) +
                                      BigDecimal(cached_aggregation.max_aggregation_with_proration)
        elsif persisted_pro_rata < 1
          target_result.aggregation = result_with_proration.negative? ? 0 : result_with_proration
          target_result.current_usage_units = aggregation_without_proration.current_usage_units
        else
          target_result.aggregation = value_without_proration
          target_result.current_usage_units = aggregation_without_proration.current_usage_units
        end
      end

      # NOTE: Full period duration to take upgrade, terminate
      #       or start on non-anniversary day into account
      def period_duration
        @period_duration ||= Subscriptions::DatesService.new_instance(
          subscription,
          to_datetime + 1.day,
          current_usage: subscription.terminated? && subscription.upgraded?,
        ).charges_duration_in_days
      end

      # NOTE: when subscription is terminated or upgraded,
      #       we want to bill the persisted metrics at prorata of the full period duration.
      #       ie: the number of day of the terminated period divided by number of days without termination
      def persisted_pro_rata
        Utils::DatetimeService.date_diff_with_timezone(
          from_datetime,
          to_datetime,
          subscription.customer.applicable_timezone,
        ).fdiv(period_duration)
      end

      attr_accessor :options

      private

      attr_reader :base_aggregator

      def previous_charge_fee
        subscription_ids = customer.subscriptions
          .where(external_id: subscription.external_id)
          .pluck(:id)

        Fee.joins(:charge)
          .where(charge: { billable_metric_id: billable_metric.id })
          .where(charge: { prorated: true })
          .where(subscription_id: subscription_ids, fee_type: :charge, group_id: group&.id)
          .where("CAST(fees.properties->>'charges_to_datetime' AS timestamp) < ?", boundaries[:to_datetime])
          .order(created_at: :desc)
          .first
      end
    end
  end
end
