# frozen_string_literal: true

module Types
  module Groups
    class Usage < Types::BaseObject
      graphql_name "GroupUsage"

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :id, ID, null: false
      field :invoice_display_name, String, null: true
      field :key, String, null: true
      field :units, GraphQL::Types::Float, null: false
      field :value, String, null: false
    end
  end
end
