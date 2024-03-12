# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class ChargeFilter < Types::BaseObject
        graphql_name 'ChargeFilterUsage'

        field :id, ID, null: false, method: :filter_id

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :invoice_display_name, String, null: true
        field :units, GraphQL::Types::Float, null: false
        field :values, Types::ChargeFilters::Values, null: false, method: :to_h
      end
    end
  end
end
