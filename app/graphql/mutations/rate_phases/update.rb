# frozen_string_literal: true

module Mutations
  module RatePhases
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "UpdateRatePhase"
      description "Updates a single phase, addressed by its code within the entry"

      argument :billing_interval_cycle_count, Integer, required: false
      argument :code, String, required: true
      argument :name, String, required: false
      argument :new_code, String, required: false
      argument :plan_applied_rate_card_id, ID, required: true

      type Types::RatePhases::Object

      def resolve(**args)
        plan_rate_card = PlanRateCard
          .where(organization: current_organization)
          .find_by(id: args[:plan_applied_rate_card_id])

        rate_phase = plan_rate_card&.rate_phases&.find_by(code: args[:code])

        params = args.except(:plan_applied_rate_card_id, :code, :new_code)
        params[:code] = args[:new_code] if args.key?(:new_code)

        result = ::RatePhases::UpdateService.call(rate_phase:, params:)

        result.success? ? result.rate_phase : result_error(result)
      end
    end
  end
end
