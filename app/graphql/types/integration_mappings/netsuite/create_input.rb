# frozen_string_literal: true

module Types
  module IntegrationMappings
    module Netsuite
      class CreateInput < Types::BaseInputObject
        graphql_name 'CreateNetsuiteIntegrationMappingInput'

        argument :mappable_id, ID, required: true
        argument :mappable_type, Types::IntegrationMappings::Netsuite::MappableTypeEnum, required: true
        argument :netsuite_account_code, String, required: true
        argument :netsuite_id, String, required: true
        argument :netsuite_name, String, required: false
      end
    end
  end
end
