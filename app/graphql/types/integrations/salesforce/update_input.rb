# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Integrations
    class Salesforce
      class UpdateInput < Types::BaseInputObject
        graphql_name "UpdateSalesforceIntegrationInput"

        argument :id, ID, required: false

        argument :code, String, required: false
        argument :instance_id, String, required: false
        argument :name, String, required: false
      end
    end
  end
end
