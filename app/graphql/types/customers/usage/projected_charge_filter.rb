# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class ProjectedChargeFilter < Types::BaseObject
        graphql_name "ProjectedChargeFilterUsage"

        delegate :units, :amount_cents, to: :projection, prefix: :projected
        delegate :units, :amount_cents, :events_count, to: :fee

        field :id, ID, null: true

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :invoice_display_name, String, null: true
        field :presentation_breakdowns, [Types::Customers::Usage::PresentationBreakdown], null: true
        field :pricing_unit_amount_cents, GraphQL::Types::BigInt, null: true
        field :pricing_unit_projected_amount_cents, GraphQL::Types::BigInt, null: true
        field :projected_amount_cents, GraphQL::Types::BigInt, null: false
        field :projected_presentation_breakdowns, [Types::Customers::Usage::PresentationBreakdown], null: true
        field :projected_units, GraphQL::Types::Float, null: false
        field :units, GraphQL::Types::Float, null: false
        field :values, Types::ChargeFilters::Values, null: false

        def id
          fee.charge_filter_id
        end

        def values
          fee.charge_filter&.to_h || {} # rubocop:disable Lint/RedundantSafeNavigation
        end

        def pricing_unit_amount_cents
          fee.pricing_unit_usage&.amount_cents
        end

        def pricing_unit_projected_amount_cents
          projection.pricing_unit_amount_cents
        end

        def invoice_display_name
          fee.charge_filter&.invoice_display_name
        end

        def presentation_breakdowns
          @presentation_breakdowns ||= Types::Fees::PresentationBreakdownBuilder.call(fee, filter: Types::Fees::PresentationBreakdownBuilder::ALL, filter_breakdown: Types::Fees::PresentationBreakdownBuilder::ALL)
        end

        def projected_presentation_breakdowns
          return [] if presentation_breakdowns.empty?

          projection.presentation_breakdowns
        end

        private

        def projection
          @projection ||= object.projection
        end

        def fee
          object.fees.sole
        end
      end
    end
  end
end
