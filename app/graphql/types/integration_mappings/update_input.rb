# frozen_string_literal: true

module Types
  module IntegrationMappings
    class UpdateInput < Types::BaseInputObject
      graphql_name "UpdateIntegrationMappingInput"

      argument :external_account_code, String, required: false
      argument :external_id, String, required: false
      argument :external_name, String, required: false
      argument :id, ID, required: true

      # DEPRECATED: These fields are not used anymore and will be removed in a future release once the frontend is
      #             updated to not use them anymore.
      argument :integration_id, ID, required: false
      argument :mappable_id, ID, required: false
      argument :mappable_type, Types::IntegrationMappings::MappableTypeEnum, required: false
    end
  end
end
