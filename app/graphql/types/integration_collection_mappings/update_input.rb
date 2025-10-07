# frozen_string_literal: true

module Types
  module IntegrationCollectionMappings
    class UpdateInput < Types::BaseInputObject
      graphql_name "UpdateIntegrationCollectionMappingInput"

      argument :id, ID, required: true

      argument :external_account_code, String, required: false
      argument :external_id, String, required: false
      argument :external_name, String, required: false
      argument :tax_code, String, required: false
      argument :tax_nexus, String, required: false
      argument :tax_type, String, required: false

      # @deprecated This field is deprecated and will be ignored. Integration ID cannot be updated.
      argument :integration_id, ID, required: false
      # @deprecated This field is deprecated and will be ignored. Mapping type cannot be updated.
      argument :mapping_type, Types::IntegrationCollectionMappings::MappingTypeEnum, required: false
    end
  end
end
