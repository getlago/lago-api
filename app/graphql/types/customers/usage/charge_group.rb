# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class ChargeGroup < Types::BaseObject
        graphql_name "GroupUsage"

        field :id, ID, null: false, method: :group_id

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :invoice_display_name, String, null: true
        field :key, String, null: true
        field :units, GraphQL::Types::Float, null: false
        field :value, String, null: false

        def key
          object.group.parent&.value || object.group.key
        end

        def value
          object.group.value
        end
      end
    end
  end
end
