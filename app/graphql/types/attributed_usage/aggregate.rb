# frozen_string_literal: true

module Types
  module AttributedUsage
    class Aggregate < Types::BaseObject
      graphql_name "AttributedUsageAggregate"

      field :amount_cents, GraphQL::Types::BigInt, null: true, description: "Null with the units basis"
      field :charges_usage, [Types::AttributedUsage::ChargeUsage], null: false, method: :cells
      field :events_count, Integer, null: false
      field :precise_amount_cents, GraphQL::Types::Float, null: true, description: "Null with the units basis"

      def amount_cents
        object.amount_cents&.round
      end

      def precise_amount_cents
        object.amount_cents&.to_f
      end
    end
  end
end
