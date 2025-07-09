# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class Charge < Types::BaseObject
        graphql_name "ChargeUsage"

        delegate :projected_units, :projected_amount_cents, to: :usage_calculator

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :id, ID, null: false
        field :pricing_unit_amount_cents, GraphQL::Types::BigInt, null: true
        field :projected_amount_cents, GraphQL::Types::BigInt, null: false
        field :projected_units, GraphQL::Types::Float, null: false
        field :units, GraphQL::Types::Float, null: false

        field :billable_metric, Types::BillableMetrics::Object, null: false
        field :charge, Types::Charges::Object, null: false
        field :filters, [Types::Customers::Usage::ChargeFilter], null: true
        field :grouped_usage, [Types::Customers::Usage::GroupedUsage], null: false

        def id
          SecureRandom.uuid
        end

        def units
          usage_calculator.current_units
        end

        def events_count
          object.sum(&:events_count)
        end

        def amount_cents
          usage_calculator.current_amount_cents
        end

        def pricing_unit_amount_cents
          return if charge.applied_pricing_unit.nil?

          object.map(&:pricing_unit_usage).sum(&:amount_cents)
        end

        def charge
          object.first.charge
        end

        def billable_metric
          object.first.billable_metric
        end

        def filters
          return [] unless object.first.has_charge_filters?

          object.sort_by { |f| f.charge_filter&.display_name.to_s }
        end

        def grouped_usage
          return [] unless object.any? { |f| f.grouped_by.present? }

          object.group_by(&:grouped_by).values
        end

        private

        def usage_calculator
          @usage_calculator ||= begin
            first_fee = object.first
            from = first_fee.properties["from_datetime"]
            to = first_fee.properties["to_datetime"]
            duration = first_fee.properties["charges_duration"]

            SubscriptionUsageFee.new(
              fees: object,
              from_datetime: from,
              to_datetime: to,
              charges_duration_in_days: duration
            )
          end
        end
      end
    end
  end
end
