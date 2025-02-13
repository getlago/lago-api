# frozen_string_literal: true

module Mutations
  module Plans
    class Destroy < BaseMutation
      include AuthenticableApiUser

      REQUIRED_PERMISSION = "plans:delete"

      graphql_name "DestroyPlan"
      description "Deletes a Plan"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        plan = context[:current_user].plans.find_by(id:)
        result = ::Plans::PrepareDestroyService.call(plan:)

        result.success? ? result.plan : result_error(result)
      end
    end
  end
end
