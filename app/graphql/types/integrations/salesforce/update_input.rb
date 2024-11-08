# frozen_string_literal: true

module Types
  module Integrations
    class Salesforce
      class UpdateInput < Types::BaseInputObject
        graphql_name 'UpdateSalesforceIntegrationInput'

        argument :id, ID, required: false

        argument :instance_id, String, required: false
        argument :name, String, required: false
      end
    end
  end
end
