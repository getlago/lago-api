# frozen_string_literal: true

module Mutations
  module RatePhases
    class Create < BaseMutation
      include RequiresProductCatalog
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "CreateRatePhase"
      description "Inserts a phase into a plan rate card's sequence"

      input_object_class Types::RatePhases::CreateInput
      type Types::RatePhases::Object

      def resolve(**args)
        plan_rate_card = PlanRateCard
          .where(organization: current_organization)
          .find_by(id: args[:plan_applied_rate_card_id])

        result = ::RatePhases::CreateService.call(
          plan_rate_card:,
          params: args.except(:plan_applied_rate_card_id)
        )

        result.success? ? result.rate_phase : result_error(result)
      end
    end
  end
end
