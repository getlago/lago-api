# frozen_string_literal: true

module Types
  module Customers
    module AppliedTaxes
      class Object < Types::BaseObject
        graphql_name 'CustomerAppliedTax'

        field :id, ID, null: false

        field :customer, Types::Customers::Object, null: false
        field :tax, Types::Taxes::Object, null: false

        field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      end
    end
  end
end
