# frozen_string_literal: true

module Mutations
  module PlanProductItems
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "CreatePlanProductItem"
      description "Assigns a product item to a plan"

      input_object_class Types::PlanProductItems::CreateInput
      type Types::PlanProductItems::Object

      def resolve(**args)
        plan = current_organization.plans.find_by(id: args[:plan_id])

        result = ::PlanProductItems::CreateService.call(plan:, params: args.except(:plan_id))

        result.success? ? result.plan_product_item : result_error(result)
      end
    end
  end
end
