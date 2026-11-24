# frozen_string_literal: true

module Types
  module Integrations
    class AgentStorefront
      class CreateInput < Types::BaseInputObject
        graphql_name "CreateAgentStorefrontIntegrationInput"

        argument :code, String, required: true
        argument :name, String, required: true
        argument :payment_provider_code, String, required: true

        argument :plans, [Types::Integrations::AgentStorefront::PlanInput], required: false
        argument :resource_endpoint, String, required: false
        argument :resource_instructions, String, required: false
      end
    end
  end
end
