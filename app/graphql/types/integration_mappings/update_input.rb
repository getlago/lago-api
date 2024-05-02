# frozen_string_literal: true

module Types
  module IntegrationMappings
    class UpdateInput < Types::BaseInputObject
      graphql_name 'UpdateIntegrationMappingInput'

      argument :external_account_code, String, required: false
      argument :external_id, String, required: false
      argument :external_name, String, required: false
      argument :id, ID, required: true
      argument :integration_id, ID, required: false
      argument :mappable_id, ID, required: false
      argument :mappable_type, Types::IntegrationMappings::MappableTypeEnum, required: false
    end
  end
end
