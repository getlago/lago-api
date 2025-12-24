# frozen_string_literal: true

module Types
  class MembershipType < Types::BaseObject
    field :id, ID, null: false

    field :organization, Types::Organizations::OrganizationType, null: false
    field :user, Types::UserType, null: false

    field :permissions, Types::PermissionsType, null: false,
      deprecation_reason: "Use permissions enum instead"
    field :role, Types::Memberships::RoleEnum,
      deprecation_reason: "Use roles instead"
    field :roles, [String], null: false
    field :status, Types::Memberships::StatusEnum, null: false

    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :revoked_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def permissions
      object.permissions_hash.transform_keys { |key| key.tr(":", "_") }
    end

    def role
      (roles.map(&:downcase) & %w[admin finance manager]).first
    end

    def roles
      @roles ||= object.roles.pluck(:name)
    end
  end
end
