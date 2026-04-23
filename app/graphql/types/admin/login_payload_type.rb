# frozen_string_literal: true

module Types
  module Admin
    class LoginPayloadType < Types::BaseObject
      graphql_name "AdminLoginPayload"
      description "Login payload returned to Lago staff users"

      field :token, String, null: false
      field :user, Types::UserType, null: false
      field :role, String, null: false
      field :allowed_integrations, [String], null: false
      field :reason_categories, [Types::Admin::ReasonCategoryEnum], null: false
    end
  end
end
