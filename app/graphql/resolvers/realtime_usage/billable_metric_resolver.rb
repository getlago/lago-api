# frozen_string_literal: true

module Resolvers
  module RealtimeUsage
    class BillableMetricResolver < BaseResolver
      description "Query the real-time usage of a billable metric, per period and per dimension"

      argument :billable_metric_code, String, required: true
      argument :dimension_keys, [String], required: false

      type Types::RealtimeUsage::BillableMetric, null: false

      def resolve(billable_metric_code:, dimension_keys: nil, **args)
        billable_metric = current_organization.billable_metrics.find_by(code: billable_metric_code)
        return not_found_error(resource: "billable_metric") unless billable_metric

        result = ::RealtimeUsage::Reports::BillableMetricsService.call(
          billable_metrics: [billable_metric],
          dimension_keys:,
          **report_filters(**args)
        )
        return result_error(result) unless result.success?

        result.billable_metrics.first ||
          validation_error(messages: {billable_metric_code: ["unsupported_aggregation_type"]})
      end
    end
  end
end
