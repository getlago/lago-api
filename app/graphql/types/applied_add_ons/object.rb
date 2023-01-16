# frozen_string_literal: true

module Types
  module AppliedAddOns
    class Object < Types::BaseObject
      graphql_name 'AppliedAddOn'

      field :id, ID, null: false
      field :add_on, Types::AddOns::Object, null: false

      field :amount_cents, GraphQL::Types::BigInt, null: false
      field :amount_currency, Types::CurrencyEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
