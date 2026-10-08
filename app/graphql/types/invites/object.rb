# frozen_string_literal: true

module Types
  module Invites
    class Object < Types::BaseObject
      graphql_name "Invite"

      field :organization, Types::Organizations::OrganizationType, null: false
      field :recipient, Types::MembershipType, null: false

      field :id, ID, null: false

      field :email, String, null: false
      field :roles, [String], null: false
      field :status, Types::Invites::StatusTypeEnum, null: false
      field :token, String, null: true

      field :accepted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :revoked_at, GraphQL::Types::ISO8601DateTime, null: true

      # The token is the only secret needed to accept an invite, so it is only
      # exposed to members who could have created this invite themselves.
      def token
        return unless context.dig(:permissions, "organization:members:create")

        if object.roles.include?("admin") && !context[:current_membership]&.admin?
          nil
        else
          object.token
        end
      end
    end
  end
end
