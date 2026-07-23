# frozen_string_literal: true

module Mutations
  module PlanRateCards
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "plans:update"

      graphql_name "CreatePlanRateCard"
      description "Assigns a product item to a plan"

      input_object_class Types::PlanRateCards::CreateInput
      type Types::PlanRateCards::Object

      def resolve(**args)
        plan = current_organization.plans.find_by(id: args[:plan_id])

        result = ::PlanRateCards::CreateService.call(plan:, params: args.except(:plan_id))

        result.success? ? result.plan_rate_card : result_error(result)
      end
    end
  end
end
