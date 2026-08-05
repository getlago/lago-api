# frozen_string_literal: true

module Types
  module Integrations
    class EntraId
      class CreateInput < Types::BaseInputObject
        graphql_name "CreateEntraIdIntegrationInput"

        argument :client_id, String, required: true
        argument :client_secret, String, required: true
        argument :domain, String, required: true
        argument :host, String, required: false
        argument :tenant_id, String, required: true
      end
    end
  end
end
