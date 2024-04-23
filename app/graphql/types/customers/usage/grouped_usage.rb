# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class GroupedUsage < Types::BaseObject
        graphql_name 'GroupedChargeUsage'

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :units, GraphQL::Types::Float, null: false

        field :filters, [Types::Customers::Usage::ChargeFilter], null: true
        field :grouped_by, GraphQL::Types::JSON, null: true

        def amount_cents
          object.sum(&:amount_cents)
        end

        def events_count
          object.sum(&:events_count)
        end

        def units
          object.map { |f| BigDecimal(f.units) }.sum
        end

        def grouped_by
          object.first.grouped_by
        end

        def filters
          return [] unless object.first.has_charge_filters?

          object.sort_by { |f| f.charge_filter&.display_name }
        end
      end
    end
  end
end
