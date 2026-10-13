# frozen_string_literal: true

module Types
  module AttributedUsage
    class ChargeUsage < Types::BaseObject
      graphql_name "AttributedUsageChargeUsage"

      field :charge, Types::Charges::Object, null: false
      field :charge_filter, Types::ChargeFilters::Object, null: true

      field :amount_cents, GraphQL::Types::BigInt, null: true, description: "Null when the charge is not priced"
      field :events_count, Integer, null: false
      field :precise_amount_cents, GraphQL::Types::Float, null: true, description: "Null when the charge is not priced"
      field :units, GraphQL::Types::Float, null: false

      def amount_cents
        object.amount_cents&.round
      end

      def precise_amount_cents
        object.amount_cents&.to_f
      end
    end
  end
end
