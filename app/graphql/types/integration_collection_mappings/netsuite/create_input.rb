# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    module Netsuite
      class CreateInput < Types::BaseInputObject
        graphql_name 'CreateNetsuiteIntegrationCollectionMappingInput'

        argument :mapping_type, Types::IntegrationCollectionMappings::Netsuite::MappingTypeEnum, required: true
        argument :netsuite_account_code, String, required: true
        argument :netsuite_id, String, required: true
        argument :netsuite_name, String, required: false
      end
    end
  end
end
