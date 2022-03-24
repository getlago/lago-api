# frozen_string_literal: true

module Mutations
  module BillableMetrics
    class Create < BaseMutation
      include AuthenticableApiUser

      graphql_name 'CreateBillableMetric'
      description 'Creates a new Billable metric'

      argument :organization_id, String, required: true
      argument :name, String, required: true
      argument :code, String, required: true
      argument :description, String
      argument :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, required: true

      type Types::BillableMetrics::Object

      def resolve(**args)
        result = BillableMetricsService.new(context[:current_user]).create(**args)

        result.success? ? result.billable_metric : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
