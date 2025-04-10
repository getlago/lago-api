# frozen_string_literal: true

module Mutations
  module Plans
    class Update < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "UpdatePlan"
      description "Updates an existing Plan"

      input_object_class Types::Plans::UpdateInput
      type Types::Plans::Object

      def resolve(**args)
        args[:charges].map!(&:to_h)
        plan = context[:current_user].plans.find_by(id: args[:id])

        result = ::Plans::UpdateService.call(plan:, params: args)
        result.success? ? result.plan : result_error(result)
      end
    end
  end
end
