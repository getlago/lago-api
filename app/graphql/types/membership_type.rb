# frozen_string_literal: true

module Types
  class MembershipType < Types::BaseObject
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :id, ID, null: false
    field :organization, Types::OrganizationType, null: false
    field :permissions, Types::PermissionsType, null: false
    field :revoked_at, GraphQL::Types::ISO8601DateTime, null: false
    field :role, String, null: true
    field :status, Types::Memberships::StatusEnum, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :user, Types::UserType, null: false
  end
end
