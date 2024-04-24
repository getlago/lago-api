# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    module Netsuite
      class UpdateInput < Types::BaseInputObject
        graphql_name 'UpdateNetsuiteIntegrationCollectionMappingInput'

        argument :id, ID, required: true

        argument :external_account_code, String, required: false
        argument :external_id, String, required: false
        argument :external_name, String, required: false
        argument :integration_id, ID, required: false
        argument :mapping_type, Types::IntegrationCollectionMappings::Netsuite::MappingTypeEnum, required: false
      end
    end
  end
end
