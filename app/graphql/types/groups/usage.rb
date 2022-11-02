# frozen_string_literal: true

module Types
  module Groups
    class Usage < Types::BaseObject
      graphql_name 'GroupUsage'

      field :id, ID, null: false
      field :key, String, null: true
      field :value, String, null: false
      field :units, GraphQL::Types::Float, null: false
      field :amount_cents, GraphQL::Types::BigInt, null: false
    end
  end
end
