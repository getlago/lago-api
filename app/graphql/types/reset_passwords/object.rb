# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module ResetPasswords
    class Object < Types::BaseObject
      graphql_name "ResetPassword"
      description "ResetPassword type"

      field :user, Types::UserType, null: false

      field :id, ID, null: false
      field :token, String, null: false

      field :expire_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
