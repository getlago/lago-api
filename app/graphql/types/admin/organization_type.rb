# frozen_string_literal: true

module Types
  module Admin
    class OrganizationType < Types::BaseObject
      graphql_name "AdminOrganization"

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :email, String, null: true
      field :feature_flags, [String], null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :premium_integrations, [String], null: false

      def feature_flags
        object.feature_flags.select { |flag| FeatureFlag.valid?(flag) }
      end
    end
  end
end
