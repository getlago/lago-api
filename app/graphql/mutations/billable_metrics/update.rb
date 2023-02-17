# frozen_string_literal: true

module Mutations
  module BillableMetrics
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdateBillableMetric'
      description 'Updates an existing Billable metric'

      argument :id, String, required: true
      argument :name, String, required: true
      argument :code, String, required: true
      argument :description, String
      argument :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, required: true
      argument :field_name, String, required: false
      argument :group, GraphQL::Types::JSON, required: false

      type Types::BillableMetrics::Object

      def resolve(**args)
        billable_metric = context[:current_user].billable_metrics.find_by(id: args[:id])
        result = ::BillableMetrics::UpdateService.call(billable_metric:, params: args)
        result.success? ? result.billable_metric : result_error(result)
      end
    end
  end
end
