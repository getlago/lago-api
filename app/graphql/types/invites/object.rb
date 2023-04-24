# frozen_string_literal: true

module Types
  module Invites
    class Object < Types::BaseObject
      graphql_name 'Invite'

      field :organization, Types::OrganizationType, null: false
      field :recipient, Types::MembershipType, null: false

      field :id, ID, null: false

      field :email, String, null: false
      field :status, Types::Invites::StatusTypeEnum, null: false
      field :token, String, null: false

      field :accepted_at, GraphQL::Types::ISO8601DateTime, null: false
      field :revoked_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
