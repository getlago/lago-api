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

      type Types::BillableMetrics::Object

      def resolve(**args)
        result = ::BillableMetrics::UpdateService.new(context[:current_user]).update(**args)

        result.success? ? result.billable_metric : result_error(result)
      end
    end
  end
end
