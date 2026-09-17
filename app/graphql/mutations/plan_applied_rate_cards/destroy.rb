# frozen_string_literal: true

module Mutations
  module PlanAppliedRateCards
    class Destroy < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "DestroyPlanAppliedRateCard"
      description "Removes a rate card from a plan without contracts"

      argument :id, ID, required: true

      type Types::PlanAppliedRateCards::Object

      def resolve(id:)
        plan_rate_card = PlanRateCard.where(organization: current_organization).find_by(id:)

        result = ::PlanRateCards::DestroyService.call(plan_rate_card:)

        result.success? ? result.plan_rate_card : result_error(result)
      end
    end
  end
end
