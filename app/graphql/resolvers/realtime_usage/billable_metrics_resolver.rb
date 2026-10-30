# frozen_string_literal: true

module Resolvers
  module RealtimeUsage
    class BillableMetricsResolver < BaseResolver
      description "Query the real-time usage of the billable metrics of the organization, per period and per dimension"

      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::RealtimeUsage::BillableMetric.collection_type, null: false

      def resolve(page: nil, limit: nil, **args)
        query_result = ::RealtimeUsage::BillableMetricsQuery.call(
          organization: current_organization,
          pagination: {page:, limit:}
        )
        return result_error(query_result) unless query_result.success?

        billable_metrics = query_result.billable_metrics
        result = ::RealtimeUsage::Reports::BillableMetricsService.call(
          billable_metrics: billable_metrics.to_a,
          **report_filters(**args)
        )
        return result_error(result) unless result.success?

        Kaminari.paginate_array(
          result.billable_metrics,
          limit: billable_metrics.limit_value,
          offset: billable_metrics.offset_value,
          total_count: billable_metrics.total_count
        )
      end
    end
  end
end
