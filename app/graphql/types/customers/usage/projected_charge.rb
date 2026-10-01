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
          object.sum(&:events_count)
        end

        def units
          object.map { |f| BigDecimal(f.units) }.sum
        end

        def amount_cents
          object.sum(&:amount_cents)
        end

        def pricing_unit_amount_cents
          return if charge.applied_pricing_unit.nil?

          object.map(&:pricing_unit_usage).sum(&:amount_cents)
        end

        def pricing_unit_projected_amount_cents
          projection.pricing_unit_amount_cents
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

        def projected_units
          projection.units
        end

        def projected_amount_cents
          projection.amount_cents
        end

        def presentation_breakdowns
          @presentation_breakdowns ||= Types::Fees::PresentationBreakdownBuilder.call(
            object,
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
          @projection ||= context[:usage_projections].for(object)
        end
      end
    end
  end
end
