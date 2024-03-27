# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class ChargeFilter < Types::BaseObject
        graphql_name 'ChargeFilterUsage'

        field :id, ID, null: false, method: :charge_filter_id

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :invoice_display_name, String, null: true
        field :units, GraphQL::Types::Float, null: false
        field :values, Types::ChargeFilters::Values, null: false

        def values
          object.charge_filter&.to_h || {} # rubocop:disable Lint/RedundantSafeNavigation
        end

        def invoice_display_name
          object.charge_filter&.display_name
        end
      end
    end
  end
end
