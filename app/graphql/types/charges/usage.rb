# frozen_string_literal: true

module Types
  module Charges
    class Usage < Types::BaseObject
      graphql_name 'ChargeUsage'

      field :units, GraphQL::Types::Float, null: false
      field :amount_cents, GraphQL::Types::BigInt, null: false

      field :charge, Types::Charges::Object, null: false
      field :billable_metric, Types::BillableMetrics::Object, null: false
      field :group, Types::Groups::Object, null: true
    end
  end
end
