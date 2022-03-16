# frozen_string_literal: true

module Mutations
  class CreateBillableMetric < BaseMutation
    include AuthenticableApiUser

    argument :organization_id, String, required: true
    argument :name, String, required: true
    argument :code, String, required: true
    argument :description, String
    argument :billable_period, Types::BillableMetrics::BillablePeriodEnum, required: true
    argument :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, required: true
    argument :pro_rata, GraphQL::Types::Boolean, required: true
    argument :properties, GraphQL::Types::JSON

    type Types::BillableMetrics::BillableMetricObject

    def resolve(**args)
      result = BillableMetricsService.new(context[:current_user]).create(**args)

      result.success? ? result.billable_metric : execution_error(code: result.error_code, message: result.error)
    end
  end
end
