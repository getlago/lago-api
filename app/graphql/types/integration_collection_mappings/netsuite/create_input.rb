# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    module Netsuite
      class CreateInput < Types::BaseInputObject
        graphql_name 'CreateNetsuiteIntegrationCollectionMappingInput'

        argument :integration_id, ID, required: true
        argument :mapping_type, Types::IntegrationCollectionMappings::Netsuite::MappingTypeEnum, required: true
        argument :netsuite_account_code, String, required: false
        argument :netsuite_id, String, required: true
        argument :netsuite_name, String, required: false
      end
    end
  end
end
