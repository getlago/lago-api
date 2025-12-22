# frozen_string_literal: true

module Types
  module IntegrationCustomers
    class NetsuiteV2 < Types::BaseObject
      graphql_name "NetsuiteV2Customer"

      field :external_customer_id, String, null: true
      field :id, ID, null: false
      field :integration_code, String, null: true
      field :integration_id, ID, null: true
      field :integration_type, Types::Integrations::IntegrationTypeEnum, null: true
      field :subsidiary_id, String, null: true
      field :sync_with_provider, Boolean, null: true

      def integration_type
        object.integration&.type
        case object.integration&.type
        when "Integrations::NetsuiteV2Integration"
          "netsuite_v2"
        end
      end

      def integration_code
        object.integration&.code
      end
    end
  end
end
