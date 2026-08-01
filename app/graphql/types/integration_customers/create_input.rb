# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class CreateInput < Types::BaseInputObject
      graphql_name "CreateIntegrationCustomerInput"
      description "Create integration customer input arguments"

      argument :customer_id, ID, required: true
      argument :integration_id, ID, required: true

      argument :code, String, required: false
      argument :external_customer_id, String, required: false
      argument :subsidiary_id, String, required: false
      argument :sync_with_provider, Boolean, required: false
      argument :targeted_object, Types::Integrations::Hubspot::TargetedObjectsEnum, required: false
    end
  end
end
