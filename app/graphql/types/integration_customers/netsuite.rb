# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class Netsuite < Types::BaseObject
      graphql_name 'NetsuiteCustomer'

      field :external_customer_id, String, null: true
      field :id, ID, null: false
      field :integration, Types::Integrations::IntegrationTypeEnum, null: true
      field :integration_code, String, null: true
      field :subsidiary_id, String, null: true
      field :sync_with_provider, Boolean, null: true
    end
  end
end
