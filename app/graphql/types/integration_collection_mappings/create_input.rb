# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    class CreateInput < Types::BaseInputObject
      graphql_name 'CreateIntegrationCollectionMappingInput'

      argument :external_account_code, String, required: false
      argument :external_id, String, required: true
      argument :external_name, String, required: false
      argument :integration_id, ID, required: true
      argument :mapping_type, Types::IntegrationCollectionMappings::MappingTypeEnum, required: true
    end
  end
end
