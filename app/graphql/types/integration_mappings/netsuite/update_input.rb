# frozen_string_literal: true

module Types
  module IntegrationMappings
    module Netsuite
      class UpdateInput < Types::BaseInputObject
        graphql_name 'UpdateNetsuiteIntegrationMappingInput'

        argument :netsuite_account_code, String, required: false
        argument :netsuite_id, String, required: false
        argument :netsuite_name, String, required: false
      end
    end
  end
end
