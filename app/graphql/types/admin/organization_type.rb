# frozen_string_literal: true

module Types
  module Admin
    class OrganizationType < Types::BaseObject
      graphql_name "AdminOrganization"

      include Types::Organizations::EnvironmentFields

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :email, String, null: true
      field :feature_flags, [String], null: false
      field :id, ID, null: false
      field :name, String, null: false
      field :premium_integrations, [String], null: false

      def feature_flags
        object.feature_flags.select { |flag| FeatureFlag.valid?(flag) }
      end

      private

      # Admin-only type: the pair is shown without the membership gate of the user-facing types.
      def linked_organization(association)
        dataloader.with(Sources::ActiveRecordAssociation, association).load(object)
      end
    end
  end
end
