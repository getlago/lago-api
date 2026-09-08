# frozen_string_literal: true

module Mutations
  module RatePhases
    class Destroy < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "DestroyRatePhase"
      description "Removes a single phase; deleting an indefinite terminal phase promotes its predecessor"

      argument :code, String, required: true
      argument :plan_applied_rate_card_id, ID, required: true

      type Types::RatePhases::Object

      def resolve(**args)
        plan_rate_card = PlanRateCard
          .where(organization: current_organization)
          .find_by(id: args[:plan_applied_rate_card_id])

        rate_phase = plan_rate_card&.rate_phases&.find_by(code: args[:code])

        result = ::RatePhases::DestroyService.call(rate_phase:)

        result.success? ? result.rate_phase : result_error(result)
      end
    end
  end
end
