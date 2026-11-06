# frozen_string_literal: true

module Types
  module Admin
    class OrganizationType < Types::BaseObject
      graphql_name "AdminOrganization"

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :email, String, null: true
      field :environment, Types::Organizations::EnvironmentEnum, null: false
      field :feature_flags, [String], null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :premium_integrations, [String], null: false
      field :production_organization, Types::Organizations::LinkedOrganizationType
      field :sandbox_organization, Types::Organizations::LinkedOrganizationType
      field :self_serve, Boolean, null: false

      # Admin-only type: the pair is shown without the membership gate of the user-facing types.
      dataload_association :production_organization, :sandbox_organization

      def feature_flags
        object.feature_flags.select { |flag| FeatureFlag.valid?(flag) }
      end
    end
  end
end
