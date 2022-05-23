# frozen_string_literal: true

module Types
  module AddOns
    class Object < Types::BaseObject
      graphql_name 'AddOn'

      field :id, ID, null: false
      field :organization, Types::OrganizationType

      field :name, String, null: false
      field :code, String, null: false
      field :description, String, null: true

      field :amount_cents, Integer, null: false
      field :amount_currency, Types::CurrencyEnum, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
