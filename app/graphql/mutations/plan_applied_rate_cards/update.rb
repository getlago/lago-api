# frozen_string_literal: true

module Mutations
  module PlanAppliedRateCards
    class Update < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "UpdatePlanAppliedRateCard"
      description "Updates a rate card applied to a plan without contracts"

      input_object_class Types::PlanAppliedRateCards::UpdateInput
      type Types::PlanAppliedRateCards::Object

      def resolve(id:, **args)
        plan_rate_card = PlanRateCard.where(organization: current_organization).find_by(id:)

        result = ::PlanRateCards::UpdateService.call(plan_rate_card:, params: args)

        result.success? ? result.plan_rate_card : result_error(result)
      end
    end
  end
end
