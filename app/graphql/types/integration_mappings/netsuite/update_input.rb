# frozen_string_literal: true

module Types
  module IntegrationMappings
    module Netsuite
      class UpdateInput < Types::BaseInputObject
        graphql_name 'UpdateNetsuiteIntegrationMappingInput'

        argument :external_account_code, String, required: false
        argument :external_id, String, required: false
        argument :external_name, String, required: false
        argument :id, ID, required: true
        argument :integration_id, ID, required: false
        argument :mappable_id, ID, required: false
        argument :mappable_type, Types::IntegrationMappings::Netsuite::MappableTypeEnum, required: false
      end
    end
  end
end
