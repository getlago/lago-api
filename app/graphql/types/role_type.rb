# frozen_string_literal: true

module Types
  class RoleType < Types::BaseObject
    field :admin, Boolean, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :description, String, null: true
    field :id, ID, null: false
    field :name, String, null: false
    field :permissions, [PermissionEnum], null: false
  end
end
