# frozen_string_literal: true

module Types
  module Integrations
    class AgentStorefront
      class UpdateInput < Types::BaseInputObject
        graphql_name "UpdateAgentStorefrontIntegrationInput"

        argument :id, ID, required: true

        argument :code, String, required: false
        argument :name, String, required: false
        argument :payment_provider_code, String, required: false

        argument :plans, [Types::Integrations::AgentStorefront::PlanInput], required: false
        argument :resource_endpoint, String, required: false
        argument :resource_instructions, String, required: false
      end
    end
  end
end
