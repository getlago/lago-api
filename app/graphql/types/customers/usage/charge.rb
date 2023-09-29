# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class Charge < Types::BaseObject
        graphql_name 'ChargeUsage'

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :units, GraphQL::Types::Float, null: false

        field :billable_metric, Types::BillableMetrics::Object, null: false
        field :charge, Types::Charges::Object, null: false
        field :groups, [Types::Customers::Usage::ChargeGroup], null: true

        def units
          object.map(&:units).map(&:to_f).sum
        end

        def amount_cents
          object.sum(&:amount_cents)
        end

        def charge
          object.first.charge
        end

        def billable_metric
          object.first.billable_metric
        end

        def groups
          object
            .select(&:group)
            .sort_by { |f| f.group.name }
        end
      end
    end
  end
end
