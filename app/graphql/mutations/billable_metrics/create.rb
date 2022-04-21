# frozen_string_literal: true

module Mutations
  module BillableMetrics
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateBillableMetric'
      description 'Creates a new Billable metric'

      argument :name, String, required: true
      argument :code, String, required: true
      argument :description, String
      argument :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, required: true
      argument :field_name, String, required: false

      type Types::BillableMetrics::Object

      def resolve(**args)
        validate_organization!

        result = BillableMetricsService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.billable_metric : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
