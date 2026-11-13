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

      def feature_flags
        object.feature_flags.select { |flag| FeatureFlag.valid?(flag) }
      end

      # As in the user-facing types, every organization answers as a standalone production one with self-serve off.
      def environment
        Lago::SelfServe.enabled? ? object.environment : "production"
      end

      def self_serve
        Lago::SelfServe.enabled? && object.self_serve
      end

      # Admin-only type: the pair is shown without the membership gate of the user-facing types.
      def production_organization
        if Lago::SelfServe.enabled? && object.sandbox?
          dataloader.with(Sources::ActiveRecordAssociation, :production_organization).load(object)
        end
      end

      def sandbox_organization
        if Lago::SelfServe.enabled? && object.production?
          dataloader.with(Sources::ActiveRecordAssociation, :sandbox_organization).load(object)
        end
      end
    end
  end
end
