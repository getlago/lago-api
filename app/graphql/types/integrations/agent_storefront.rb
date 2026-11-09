# frozen_string_literal: true

module Types
  module Integrations
    class AgentStorefront < Types::BaseObject
      graphql_name "AgentStorefrontIntegration"

      field :code, String, null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :payment_provider_code, String, null: false
      field :resource_endpoint, String, null: true
      field :resource_instructions, String, null: true
      field :scope, String, null: false
    end
  end
end
