# frozen_string_literal: true

module Resolvers
  module RealtimeUsage
    class DimensionNamesResolver < BaseResolver
      description "Query the dimensions of a billable metric, biggest first, over the longest window by default"

      argument :billable_metric_code, String, required: true
      argument :limit, Integer, required: false

      type [Types::RealtimeUsage::DimensionName], null: false

      def resolve(billable_metric_code:, limit: nil, **args)
        billable_metric = current_organization.billable_metrics.find_by(code: billable_metric_code)
        return not_found_error(resource: "billable_metric") unless billable_metric

        result = ::RealtimeUsage::Reports::DimensionNamesService.call(
          billable_metric:,
          limit:,
          **report_filters(**args)
        )

        result.success? ? result.dimensions : result_error(result)
      end
    end
  end
end
