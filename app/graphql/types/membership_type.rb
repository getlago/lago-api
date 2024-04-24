# frozen_string_literal: true

module Types
  class MembershipType < Types::BaseObject
    field :id, ID, null: false

    field :organization, Types::OrganizationType, null: false
    field :user, Types::UserType, null: false

    field :permissions, Types::PermissionsType, null: false
    field :role, Types::Memberships::RoleEnum, null: true
    field :status, Types::Memberships::StatusEnum, null: false

    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :revoked_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
  end
end
