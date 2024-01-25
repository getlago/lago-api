# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class GroupedUsage < Types::BaseObject
        graphql_name 'GroupedChargeUsage'

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :units, GraphQL::Types::Float, null: false

        field :grouped_by, GraphQL::Types::JSON, null: true
        field :groups, [Types::Customers::Usage::ChargeGroup], null: true

        def groups
          object
            .select(&:group)
            .sort_by { |f| f.group.name }
        end
      end
    end
  end
end
