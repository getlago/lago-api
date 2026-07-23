# frozen_string_literal: true

module Mutations
  module RatePhases
    class Replace < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "ReplaceRatePhases"
      description "Replaces the whole ordered rate phase sequence of a plan product item"

      input_object_class Types::RatePhases::ReplaceInput
      type [Types::RatePhases::Object]

      def resolve(**args)
        plan_rate_card = PlanRateCard
          .where(organization: current_organization)
          .find_by(id: args[:plan_rate_card_id])

        result = ::RatePhases::ReplaceService.call(
          plan_rate_card:,
          phases_params: args[:rate_phases]
        )

        result.success? ? result.rate_phases : result_error(result)
      end
    end
  end
end
