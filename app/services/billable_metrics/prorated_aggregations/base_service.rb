# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class BaseService < BillableMetrics::Aggregations::BaseService
      def aggregation_without_proration
        @aggregation_without_proration ||= base_aggregator.aggregate(from_datetime:, to_datetime:, options:)
      end

      def previous_event
        @previous_event ||= base_aggregator.get_previous_event_in_interval(from_datetime:, to_datetime:)
      end

      def compute_pay_in_advance_aggregation
        return BigDecimal(0) unless event
        return BigDecimal(0) if event.properties.blank?

        result_without_proration = aggregation_without_proration.pay_in_advance_aggregation
        result.full_units_number = result_without_proration
        result.units_applied = aggregation_without_proration.units_applied

        number_of_seconds = to_datetime.in_time_zone(customer.applicable_timezone) -
                            event.timestamp.in_time_zone(customer.applicable_timezone)
        # In order to get proration coefficient we have to divide number of seconds with number
        # of seconds in one day (86400). That way we will get number of days when the service was used.
        proration_coefficient = number_of_seconds.fdiv(1.day).ceil.fdiv(period_duration)

        value = (result_without_proration * proration_coefficient).ceil(5)

        extend_event_metadata(value)

        value
      end

      # We need to extend event metadata with max_aggregation_with_proration. This attribute will be used
      # for current usage in pay_in_advance case
      def extend_event_metadata(prorated_value)
        result.max_aggregation = aggregation_without_proration.max_aggregation
        result.current_aggregation = aggregation_without_proration.current_aggregation

        unless previous_event
          result.max_aggregation_with_proration = prorated_value.to_s

          return
        end

        if BigDecimal(aggregation_without_proration.max_aggregation) >
           BigDecimal(previous_event.metadata['max_aggregation'])
          result.max_aggregation_with_proration =
            (
              BigDecimal(previous_event.metadata['max_aggregation_with_proration']) +
              prorated_value
            ).to_s
        else
          result.max_aggregation_with_proration =
            BigDecimal(previous_event.metadata['max_aggregation_with_proration'])
        end
      end

      # In current usage section two main values are presented, number of units in period and amount.
      # Proration affects only amount (calculated from aggregation) and number of units shows full number of units
      # (calculated from current_usage_units).
      def handle_current_usage(result_with_proration, is_pay_in_advance)
        value_without_proration = aggregation_without_proration.aggregation

        if !is_pay_in_advance
          result.aggregation = result_with_proration.negative? ? 0 : result_with_proration
          result.current_usage_units = value_without_proration.negative? ? 0 : value_without_proration
        elsif previous_event
          result.current_usage_units = aggregation_without_proration.current_usage_units
          result.aggregation = aggregation_without_proration.current_usage_units -
                               BigDecimal(previous_event.metadata['current_aggregation']) +
                               BigDecimal(previous_event.metadata['max_aggregation_with_proration'])
        elsif persisted_pro_rata < 1
          result.aggregation = result_with_proration.negative? ? 0 : result_with_proration
          result.current_usage_units = aggregation_without_proration.current_usage_units
        else
          result.aggregation = value_without_proration
          result.current_usage_units = aggregation_without_proration.current_usage_units
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
        ((to_datetime.to_time - from_datetime.to_time) / 1.day).ceil.fdiv(period_duration)
      end

      private

      attr_reader :base_aggregator
    end
  end
end
