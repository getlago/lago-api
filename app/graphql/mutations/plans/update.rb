# frozen_string_literal: true

module Mutations
  module Plans
    class Update < BaseMutation
      include AuthenticableApiUser

      graphql_name 'UpdatePlan'

      argument :id, String, required: true
      argument :name, String, required: true
      argument :billable_metric_ids, [String]

      type Types::Plans::Object

      def resolve(**args)
        result = PlansService.new(context[:current_user]).update(**args)

        result.success? ? result.plan : execution_error(code: result.error_code, message: result.message)
      end
    end
  end
end
