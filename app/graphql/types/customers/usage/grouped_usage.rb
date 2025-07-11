# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class GroupedUsage < Types::BaseObject
        graphql_name "GroupedChargeUsage"

        delegate :projected_units, :projected_amount_cents, to: :usage_calculator

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :id, ID, null: false
        field :projected_amount_cents, GraphQL::Types::BigInt, null: false
        field :projected_units, GraphQL::Types::Float, null: false
        field :units, GraphQL::Types::Float, null: false

        field :filters, [Types::Customers::Usage::ChargeFilter], null: true
        field :grouped_by, GraphQL::Types::JSON, null: true

        def id
          SecureRandom.uuid
        end

        def amount_cents
          usage_calculator.current_amount_cents
        end

        def events_count
          object.sum(&:events_count)
        end

        def units
          usage_calculator.current_units
        end

        def grouped_by
          object.first.grouped_by
        end

        def filters
          return [] unless object.first.has_charge_filters?

          object.sort_by { |f| f.charge_filter&.display_name.to_s }
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
