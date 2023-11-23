# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class SumService < BillableMetrics::ProratedAggregations::BaseService
      def initialize(**args)
        @base_aggregator = BillableMetrics::Aggregations::SumService.new(**args)

        super(**args)

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def aggregate(options: {})
        @options = options

        # For charges that are pay in advance on billing date we always bill full amount
        return aggregation_without_proration if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregation = compute_aggregation.ceil(5)
        result.full_units_number = aggregation_without_proration.aggregation if event.nil?

        if options[:is_current_usage]
          handle_current_usage(aggregation, options[:is_pay_in_advance])
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation
        result.count = aggregation_without_proration.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: 'aggregation_failure', message: e.message)
      end

      def compute_per_event_prorated_aggregation
        event_store.prorated_events_values(period_duration)
      end

      def per_event_aggregation
        recurring_result = recurring_value
        recurring_aggregation = recurring_result ? [BigDecimal(recurring_result)] : []
        recurring_prorated_aggregation = recurring_result ? [BigDecimal(recurring_result) * persisted_pro_rata] : []

        Result.new.tap do |result|
          result.event_aggregation = recurring_aggregation + base_aggregator.compute_per_event_aggregation
          result.event_prorated_aggregation = recurring_prorated_aggregation + compute_per_event_prorated_aggregation
        end
      end

      protected

      def compute_aggregation
        result = 0.0

        # NOTE: Billed on the full period
        result += persisted_sum || 0

        # NOTE: Added during the period
        result + (event_store.prorated_sum(period_duration:) || 0)
      end

      def persisted_sum
        event_store = event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries: { to_datetime: from_datetime },
          group:,
          event:,
        )

        event_store.use_from_boundary = false
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        event_store.prorated_sum(
          period_duration:,
          persisted_duration: Utils::DatetimeService.date_diff_with_timezone(
            from_datetime,
            to_datetime,
            subscription.customer.applicable_timezone,
          ),
        )
      end

      def recurring_value
        previous_charge_fee_units = previous_charge_fee&.units
        return previous_charge_fee_units if previous_charge_fee_units

        event_store = event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries: { to_datetime: from_datetime },
          group:,
          event:,
        )

        event_store.use_from_boundary = false
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true

        recurring_value_before_first_fee = event_store.sum

        ((recurring_value_before_first_fee || 0) <= 0) ? nil : recurring_value_before_first_fee
      end
    end
  end
end
