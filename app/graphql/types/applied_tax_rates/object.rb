# frozen_string_literal: true

module Types
  module AppliedTaxRates
    class Object < Types::BaseObject
      graphql_name 'AppliedTaxRate'

      field :id, ID, null: false

      field :customer, Types::Customers::Object, null: false
      field :tax_rate, Types::TaxRates::Object, null: false

      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
