# frozen_string_literal: true

module Types
  module Integrations
    class AgentStorefront < Types::BaseObject
      graphql_name "AgentStorefrontIntegration"

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :payment_provider, Types::PaymentProviders::Stripe, null: true, method: :stripe_provider
      field :payment_provider_code, String, null: false
      field :resource_endpoint, String, null: true
      field :resource_instructions, String, null: true
      field :scope, String, null: false

      field :agent_url, String, null: false
      field :auth_document_url, String, null: false
      field :billing_document_url, String, null: false
      field :claim_url, String, null: false

      field :plans, [Types::Integrations::AgentStorefront::Plan], null: false

      field :has_agents_with_stripe_customer, Boolean, null: false, method: :agents_with_stripe_customer?
      field :has_enrolled_agents, Boolean, null: false, method: :enrolled_agents?

      def plans
        plans_by_code = object.plans_for_sale.index_by(&:code)

        object.plans.map { |sold_plan| sold_plan.merge("plan" => plans_by_code[sold_plan["plan_code"]]) }
      end
    end
  end
end
