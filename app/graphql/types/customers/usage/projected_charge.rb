# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class ProjectedCharge < Types::BaseObject
        graphql_name "ProjectedChargeUsage"

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :events_count, Integer, null: false
        field :id, ID, null: false
        field :pricing_unit_amount_cents, GraphQL::Types::BigInt, null: true
        field :pricing_unit_projected_amount_cents, GraphQL::Types::BigInt, null: true
        field :projected_amount_cents, GraphQL::Types::BigInt, null: false
        field :projected_units, GraphQL::Types::Float, null: false
        field :units, GraphQL::Types::Float, null: false

        field :billable_metric, Types::BillableMetrics::Object, null: false
        field :charge, Types::Charges::Object, null: false
        field :filters, [Types::Customers::Usage::ProjectedChargeFilter], null: true
        field :grouped_usage, [Types::Customers::Usage::ProjectedGroupedUsage], null: false
        field :presentation_breakdowns, [Types::Customers::Usage::PresentationBreakdown], null: true
        field :projected_presentation_breakdowns, [Types::Customers::Usage::PresentationBreakdown], null: true

        def id
          SecureRandom.uuid
        end

        def events_count
          fees.sum(&:events_count)
        end

        def units
          fees.map { |f| BigDecimal(f.units) }.sum
        end

        def amount_cents
          fees.sum(&:amount_cents)
        end

        def pricing_unit_amount_cents
          return if charge.applied_pricing_unit.nil?

          fees.map(&:pricing_unit_usage).sum(&:amount_cents)
        end

        def pricing_unit_projected_amount_cents
          projection.pricing_unit_amount_cents
        end

        def charge
          fees.first.charge
        end

        def billable_metric
          fees.first.billable_metric
        end

        def filters
          return [] unless fees.first.has_charge_filters?

          fees.sort_by { |f| f.charge_filter&.display_name.to_s }.map { |fee| object.wrap([fee]) }
        end

        def grouped_usage
          return [] unless fees.any? { |f| f.grouped_by.present? }

          fees.group_by(&:grouped_by).values.map { |group_fees| object.wrap(group_fees) }
        end

        def projected_units
          projection.units
        end

        def projected_amount_cents
          projection.amount_cents
        end

        def presentation_breakdowns
          @presentation_breakdowns ||= Types::Fees::PresentationBreakdownBuilder.call(
            fees,
            filter: Types::Fees::PresentationBreakdownBuilder::UNGROUPED,
            filter_breakdown: Types::Fees::PresentationBreakdownBuilder::ALL
          )
        end

        def projected_presentation_breakdowns
          return [] if presentation_breakdowns.empty?

          projection.presentation_breakdowns
        end

        private

        def projection
          @projection ||= object.projection
        end

        def fees
          object.fees
        end
      end
    end
  end
end
