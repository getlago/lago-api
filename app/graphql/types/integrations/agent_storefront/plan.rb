# frozen_string_literal: true

module Types
  module Integrations
    class AgentStorefront
      class Plan < Types::BaseObject
        graphql_name "AgentStorefrontPlan"
        description "A plan sold to agents by an Agent Storefront"

        field :plan_code, String, null: false

        field :free_credits_cents, GraphQL::Types::BigInt, null: true
        field :maximum_topup_cents, GraphQL::Types::BigInt, null: true
        field :minimum_topup_cents, GraphQL::Types::BigInt, null: true

        # Nil once the plan is gone: the storefront keeps its code until an edit drops it.
        field :plan, Types::Plans::Object, null: true
      end
    end
  end
end
