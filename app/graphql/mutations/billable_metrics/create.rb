# frozen_string_literal: true

module Mutations
  module BillableMetrics
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateBillableMetric'
      description 'Creates a new Billable metric'

      argument :aggregation_type, Types::BillableMetrics::AggregationTypeEnum, required: true
      argument :code, String, required: true
      argument :description, String
      argument :field_name, String, required: false
      argument :group, GraphQL::Types::JSON, required: false
      argument :name, String, required: true

      type Types::BillableMetrics::Object

      def resolve(**args)
        validate_organization!

        result = ::BillableMetrics::CreateService
          .new(context[:current_user])
          .create(**args.merge(organization_id: current_organization.id))

        result.success? ? result.billable_metric : result_error(result)
      end
    end
  end
end
