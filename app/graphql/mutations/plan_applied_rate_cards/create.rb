# frozen_string_literal: true

module Mutations
  module PlanAppliedRateCards
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "CreatePlanAppliedRateCard"
      description "Applies a rate card to a plan"

      input_object_class Types::PlanAppliedRateCards::CreateInput
      type Types::PlanAppliedRateCards::Object

      def resolve(**args)
        plan = current_organization.plans.parents.find_by(id: args[:plan_id])

        result = ::PlanRateCards::CreateService.call(plan:, params: args.except(:plan_id))

        result.success? ? result.plan_rate_card : result_error(result)
      end
    end
  end
end
