# frozen_string_literal: true

module Resolvers
  module RealtimeUsage
    class BillableMetricsResolver < BaseResolver
      description "Query the real-time usage of the billable metrics of the organization, per period and per dimension"

      DEFAULT_LIMIT = 20

      argument :limit, Integer, required: false
      argument :page, Integer, required: false

      type Types::RealtimeUsage::BillableMetric.collection_type, null: false

      def resolve(page: nil, limit: nil, **args)
        billable_metrics = current_organization.billable_metrics
          .where(aggregation_type: ::RealtimeUsage::Reports::BaseService::SUPPORTED_AGGREGATION_TYPES, recurring: false)
          .order(:name, :id)
          .page(page)
          .per(limit || DEFAULT_LIMIT)

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
