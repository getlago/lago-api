# frozen_string_literal: true

module Types
  module Organizations
    # The self-serve environment of an organization and its production or sandbox pair, for the organization types
    # that show them. With self-serve off, every organization answers as a standalone production one.
    module EnvironmentFields
      extend ActiveSupport::Concern
      include ViewerMembership

      included do
        field :environment, Types::Organizations::EnvironmentEnum, null: false
        field :production_organization, Types::Organizations::LinkedOrganizationType
        field :sandbox_organization, Types::Organizations::LinkedOrganizationType
        field :self_serve, GraphQL::Types::Boolean, null: false
      end

      def environment
        Lago::SelfServe.enabled? ? object.environment : "production"
      end

      def self_serve
        Lago::SelfServe.enabled? && object.self_serve
      end

      def production_organization
        linked_organization(:production_organization) if Lago::SelfServe.enabled? && object.sandbox?
      end

      def sandbox_organization
        linked_organization(:sandbox_organization) if Lago::SelfServe.enabled? && object.production?
      end

      private

      # The user-facing types are reachable from the public invite query and from other members' memberships, so a
      # linked organization is shown only to a viewer who is an active member of it.
      def linked_organization(association)
        # Without a session nothing is shown: skip loading the linked organization.
        return if context[:current_user].nil?

        linked = dataloader.with(Sources::ActiveRecordAssociation, association).load(object)
        linked if linked && viewer_active_member?(linked.id)
      end
    end
  end
end
