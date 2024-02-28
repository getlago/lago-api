# frozen_string_literal: true

module BillableMetrics
  module ProratedAggregations
    class UniqueCountService < BillableMetrics::ProratedAggregations::BaseService
      def initialize(**args)
        @base_aggregator = BillableMetrics::Aggregations::UniqueCountService.new(**args)

        super(**args)

        event_store.aggregation_property = billable_metric.field_name
        event_store.use_from_boundary = !billable_metric.recurring
      end

      def compute_aggregation(options: {})
        aggregation_without_proration = base_aggregator.aggregate(options:)

        # For charges that are pay in advance on billing date we always bill full amount
        return aggregation_without_proration if event.nil? && options[:is_pay_in_advance] && !options[:is_current_usage]

        aggregation = event_store.prorated_unique_count.ceil(5)
        result.full_units_number = aggregation_without_proration.aggregation if event.nil?

        if options[:is_current_usage]
          handle_current_usage(
            aggregation,
            options[:is_pay_in_advance],
            target_result: result,
            aggregation_without_proration:,
          )
        else
          result.aggregation = aggregation
        end

        result.pay_in_advance_aggregation = compute_pay_in_advance_aggregation(aggregation_without_proration:)
        result.options = options
        result.count = result.aggregation
        result
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

        aggregations = event_store.grouped_prorated_unique_count
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
              aggregation_without_proration: group_result_without_proration,
            )
          else
            group_result.aggregation = aggregation_value
          end

          group_result.count = group_result.aggregation
          group_result.options = options

          group_result
        end

        result
      end

      def per_event_aggregation
        period_aggregation = event_store.prorated_unique_count_breakdown.map { |row| row['prorated_value'].ceil(5) }

        Result.new.tap do |result|
          result.event_aggregation = Array.new(period_aggregation.count) { 1 }
          result.event_prorated_aggregation = period_aggregation
        end
      end
    end
  end
end
