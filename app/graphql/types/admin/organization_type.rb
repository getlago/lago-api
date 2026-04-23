# frozen_string_literal: true

module Types
  module Admin
    class OrganizationType < Types::BaseObject
      graphql_name "AdminOrganization"
      description "Organization exposed to Lago staff only"

      field :id, ID, null: false
      field :name, String, null: false
      field :email, String
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :premium_integrations, [String], null: false
      field :premium_integrations_count, Integer, null: false
      field :customers_count, Integer, null: false

      def premium_integrations_count
        object.premium_integrations.size
      end

      def customers_count
        object.customers.size
      end
    end
  end
end
