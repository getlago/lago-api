# frozen_string_literal: true

module Mutations
  module RatePhases
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "CreateRatePhase"
      description "Inserts a phase into a plan rate card's sequence"

      argument :billing_interval_cycle_count, Integer, required: false
      argument :code, String, required: true
      argument :name, String, required: false
      argument :plan_applied_rate_card_id, ID, required: true
      argument :position, Integer, required: false

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
