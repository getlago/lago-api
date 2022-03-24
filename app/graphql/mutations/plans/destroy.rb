# frozen_string_literal: true

module Mutations
  module Plans
    class Destroy < BaseMutation
      include AuthenticableApiUser

      graphql_name 'DestroyPlan'
      description 'Deletes a Plan'

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        result = PlansService.new(context[:current_user]).destroy(id)

        result.success? ? result.plan : execution_error(code: result.error, message: result.error)
      end
    end
  end
end
