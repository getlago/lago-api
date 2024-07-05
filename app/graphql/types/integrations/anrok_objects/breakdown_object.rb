# frozen_string_literal: true

module Types
  module Integrations
    module AnrokObjects
      class BreakdownObject < Types::BaseObject
        graphql_name 'AnrokBreakdownObject'

        field :name, String, null: true
        field :rate, GraphQL::Types::Float, null: true
        field :tax_amount, GraphQL::Types::BigInt, null: true
        field :type, String, null: true

        def rate
          BigDecimal(object.rate)
        end
      end
    end
  end
end
