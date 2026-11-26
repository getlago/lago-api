# frozen_string_literal: true

module Types
  module Integrations
    class AgentStorefront
      class PlanInput < Types::BaseInputObject
        graphql_name "AgentStorefrontPlanInput"

        argument :plan_code, String, required: true

        argument :free_credits_cents, GraphQL::Types::BigInt, required: false
        argument :maximum_topup_cents, GraphQL::Types::BigInt, required: false
        argument :minimum_topup_cents, GraphQL::Types::BigInt, required: false
      end
    end
  end
end
