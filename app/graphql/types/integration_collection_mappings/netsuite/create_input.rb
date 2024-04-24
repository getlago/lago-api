# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    module Netsuite
      class CreateInput < Types::BaseInputObject
        graphql_name 'CreateNetsuiteIntegrationCollectionMappingInput'

        argument :external_account_code, String, required: false
        argument :external_id, String, required: true
        argument :external_name, String, required: false
        argument :integration_id, ID, required: true
        argument :mapping_type, Types::IntegrationCollectionMappings::Netsuite::MappingTypeEnum, required: true
      end
    end
  end
end
