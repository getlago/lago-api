# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class Avalara < Types::BaseObject
      graphql_name "AvalaraCustomer"

      field :external_customer_id, String, null: true
      field :id, ID, null: false
      field :integration_code, String, null: true
      field :integration_id, ID, null: true
      field :integration_type, Types::Integrations::IntegrationTypeEnum, null: true
      field :is_default, Boolean, null: false
      field :sync_with_provider, Boolean, null: true

      def integration_type
        "avalara"
      end

      def integration_code
        object.integration&.code
      end
    end
  end
end
