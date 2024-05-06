# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class Input < Types::BaseInputObject
      graphql_name 'IntegrationCustomerInput'

      argument :external_customer_id, String, required: false
      argument :integration, Types::Integrations::IntegrationTypeEnum, required: false
      argument :integration_code, String, required: false
      argument :subsidiary_id, String, required: false
      argument :sync_with_provider, Boolean, required: false
    end
  end
end
