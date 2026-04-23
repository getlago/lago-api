# frozen_string_literal: true

module Types
  module Admin
    class UserType < Types::BaseObject
      graphql_name "AdminUserType"
      description "An authenticated Lago staff user"

      field :id, ID, null: false
      field :email, String, null: false
      field :role, String, null: false
      field :last_sign_in_at, GraphQL::Types::ISO8601DateTime
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
