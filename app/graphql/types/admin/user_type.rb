# frozen_string_literal: true

module Types
  module Admin
    class UserType < Types::BaseObject
      graphql_name "AdminUserType"
      description "An authenticated Lago staff user (hardcoded, no DB row)"

      field :email, String, null: false
      field :role, String, null: false

      def role
        object.role.to_s
      end
    end
  end
end
