# frozen_string_literal: true

module Resolvers
  module RealtimeUsage
    class DimensionsResolver < BaseResolver
      description "Query every dimension of a billable metric, with its real-time usage per period"

      argument :billable_metric_code, String, required: true
      argument :dimension_keys, [String], required: false
      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::RealtimeUsage::DimensionRow.collection_type, null: false

      def resolve(billable_metric_code:, dimension_keys: nil, page: nil, limit: nil, **args)
        billable_metric = current_organization.billable_metrics.find_by(code: billable_metric_code)
        return not_found_error(resource: "billable_metric") unless billable_metric

        result = ::RealtimeUsage::Reports::DimensionsService.call(
          billable_metric:,
          dimension_keys:,
          page:,
          limit:,
          **report_filters(**args)
        )
        return result_error(result) unless result.success?

        Kaminari.paginate_array(
          result.dimensions,
          limit: result.limit,
          offset: (result.page - 1) * result.limit,
          total_count: result.total_count
        )
      end
    end
  end
end
