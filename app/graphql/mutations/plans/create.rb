# frozen_string_literal: true

module Mutations
  module Plans
    class Create < BaseMutation
      include AuthenticableApiUser

      description 'Creates a new plan'
      graphql_name 'CreatePlan'

      argument :organization_id, String, required: true
      argument :name, String, required: true
      argument :billable_metric_ids, [String]

      type Types::Plans::Object

      def resolve(**args)
        result = PlansService.new(context[:current_user]).create(**args)

        result.success? ? result.plan : execution_error(code: result.error_code, message: result.error)
      end
    end
  end
end
