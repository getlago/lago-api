# frozen_string_literal: true

module Types
  class UserType < Types::BaseObject
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :email, String
    field :id, ID, null: false
    field :premium, Boolean, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    # Use SafeOrganizationType to prevent traversal attack. See SafeOrganizationType for more details.
    field :organizations, [Types::SafeOrganizationType]

    def organizations
      object.memberships.active.map(&:organization)
    end

    def premium
      License.premium?
    end
  end
end
