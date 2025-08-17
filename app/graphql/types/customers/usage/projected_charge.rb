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
          projection_result.projected_pricing_unit_amount_cents
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
          calculate_projection(:projected_units, BigDecimal("0"))
        end

        def projected_amount_cents
          calculate_projection(:projected_amount_cents, 0)
        end

        private

        def calculate_projection(attribute, zero_value)
          if charge.filters.any?
            calculate_filtered_projection(attribute, zero_value)
          elsif has_grouping?
            calculate_grouped_projection(attribute)
          else
            projection_result.public_send(attribute)
          end
        end

        def calculate_filtered_projection(attribute, zero_value)
          filter_groups = object.group_by(&:charge_filter_id).values

          filter_groups.sum do |filter_fee_group|
            next zero_value unless filter_fee_group.first.charge_filter_id

            result = ::Fees::ProjectionService.call!(fees: filter_fee_group)
            result.public_send(attribute)
          end
        end

        def calculate_grouped_projection(attribute)
          grouped_fees = object.group_by(&:grouped_by).values

          grouped_fees.sum do |group_fee_list|
            result = ::Fees::ProjectionService.call!(fees: group_fee_list)
            result.public_send(attribute)
          end
        end

        def has_grouping?
          object.any? { |f| f.grouped_by.present? }
        end

        def projection_result
          @projection_result ||= ::Fees::ProjectionService.call!(fees: object)
        end
      end
    end
  end
end
