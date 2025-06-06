# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class SumService < BillableMetrics::ProratedAggregations::BaseService
      def initialize(**args)
        super
        @base_aggregator = BillableMetrics::Aggregations::SumService.new(**args)
        @base_aggregator.result = result

        event_store.numeric_property = true
        event_store.aggregation_property = billable_metric.field_name
      end

      def compute_aggregation(options: {})
        aggregation_without_proration = base_aggregator.aggregate(options:)

        # For charges that are pay in advance on billing date we always bill full amount
        return aggregation_without_proration if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregation = compute_event_aggregation.ceil(5)
        result.full_units_number = aggregation_without_proration.aggregation if event.nil?

        if options[:is_current_usage]
          handle_current_usage(
            aggregation,
            options[:is_pay_in_advance],
            target_result: result,
            aggregation_without_proration:
          )
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation(aggregation_without_proration:)
        result.count = aggregation_without_proration.count
        result.options = options
        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: "aggregation_failure", message: e.message)
      end

      # NOTE: Apply the grouped_by filter to the aggregation
      #       Result will have an aggregations attribute
      #       containing the aggregation result of each group.
      #
      #       This logic is only applicable for in arrears aggregation
      #       (exept for the current_usage update)
      #       as pay in advance aggregation will be computed on a single group
      #       with the grouped_by_values filter
      def compute_grouped_by_aggregation(options: {})
        aggregation_without_proration = base_aggregator.aggregate(options:)

        # For charges that are pay in advance on billing date we always bill full amount
        return aggregation_without_proration if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregations = compute_grouped_event_aggregation
        return empty_results if aggregations.blank?

        result.aggregations = aggregations.map do |aggregation|
          aggregation_value = aggregation[:value].ceil(5)

          group_result_without_proration = aggregation_without_proration.aggregations.find do |agg|
            agg.grouped_by == aggregation[:groups]
          end

          unless group_result_without_proration
            group_result_without_proration = empty_results.aggregations.first
            group_result_without_proration.grouped_by = aggregation[:groups]
          end

          group_result = BaseService::Result.new
          group_result.grouped_by = aggregation[:groups]
          group_result.full_units_number = group_result_without_proration&.aggregation || 0

          if options[:is_current_usage]
            handle_current_usage(
              aggregation_value,
              options[:is_pay_in_advance],
              target_result: group_result,
              aggregation_without_proration: group_result_without_proration
            )
          else
            group_result.aggregation = aggregation_value
          end

          group_result.count = group_result_without_proration&.count || 0
          group_result.options = options

          group_result
        end

        result
      rescue ActiveRecord::StatementInvalid => e
        result.service_failure!(code: "aggregation_failure", message: e.message)
      end

      def compute_per_event_prorated_aggregation
        event_store.prorated_events_values(period_duration)
      end

      def per_event_aggregation(exclude_event: false, grouped_by_values: nil)
        recurring_result = recurring_value
        recurring_aggregation = recurring_result ? [BigDecimal(recurring_result)] : []
        recurring_prorated_aggregation = recurring_result ? [BigDecimal(recurring_result) * persisted_pro_rata] : []

        ProratedPerEventAggregationResult.new.tap do |result|
          result.event_aggregation = recurring_aggregation +
            base_aggregator.per_event_aggregation(exclude_event:, grouped_by_values:).event_aggregation

          event_store.with_grouped_by_values(grouped_by_values) do
            result.event_prorated_aggregation = recurring_prorated_aggregation +
              compute_per_event_prorated_aggregation
          end
        end
      end

      protected

      def persisted_event_store_instance
        event_store = event_store_class.new(
          code: billable_metric.code,
          subscription:,
          boundaries: {to_datetime: from_datetime},
          filters:
        )

        event_store.use_from_boundary = false
        event_store.aggregation_property = billable_metric.field_name
        event_store.numeric_property = true
        event_store
      end

      def compute_event_aggregation
        result = 0.0

        # NOTE: Billed on the full period
        result += persisted_sum || 0

        # NOTE: Added during the period
        result + (event_store.prorated_sum(period_duration:) || 0)
      end

      def persisted_sum
        persisted_event_store_instance.prorated_sum(
          period_duration:,
          persisted_duration: subscription.date_diff_with_timezone(from_datetime, to_datetime)
        )
      end

      def recurring_value(grouped_by_values: nil)
        previous_charge_fee_units = previous_charge_fee(grouped_by_values:)&.units
        return previous_charge_fee_units if previous_charge_fee_units

        store = persisted_event_store_instance
        recurring_value_before_first_fee = store.with_grouped_by_values(grouped_by_values) { store.sum }

        ((recurring_value_before_first_fee || 0) <= 0) ? nil : recurring_value_before_first_fee
      end

      def compute_grouped_event_aggregation
        result = grouped_persisted_sums
        current_results = event_store.grouped_prorated_sum(period_duration:)

        current_results.each do |group_result|
          group = group_result[:groups]

          if (persisted_group = result.find { |r| r[:groups] == group })
            # NOTE: A persisted value already exists for this group
            #       We just append the value to the persisted one
            persisted_group[:value] += group_result[:value]
            next
          end

          # NOTE: Add the new group to the result
          result << group_result
        end

        result
      end

      def grouped_persisted_sums
        persisted_event_store_instance.grouped_prorated_sum(
          period_duration:,
          persisted_duration: subscription.date_diff_with_timezone(from_datetime, to_datetime)
        )
      end
    end
  end
end
