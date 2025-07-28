# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class Charge < Types::BaseObject
        graphql_name "ChargeUsage"

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
        field :filters, [Types::Customers::Usage::ChargeFilter], null: true
        field :grouped_usage, [Types::Customers::Usage::GroupedUsage], null: false

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

        def projected_units # rubocop:disable GraphQL/ResolverMethodLength
          if charge.filters.any?
            filter_groups = object.group_by(&:charge_filter_id).values
            filter_groups.sum do |filter_fee_group|
              next BigDecimal("0") unless filter_fee_group.first.charge_filter_id

              result = ::Fees::ProjectionService.call(fees: filter_fee_group).raise_if_error!
              result.projected_units
            end
          elsif object.any? { |f| f.grouped_by.present? }
            grouped_fees = object.group_by(&:grouped_by).values
            grouped_fees.sum do |group_fee_list|
              ::Fees::ProjectionService.call(fees: group_fee_list).raise_if_error!.projected_units
            end
          else
            projection_result.projected_units
          end
        end

        def projected_amount_cents # rubocop:disable GraphQL/ResolverMethodLength
          if charge.filters.any?
            filter_groups = object.group_by(&:charge_filter_id).values
            filter_groups.sum do |filter_fee_group|
              next 0 unless filter_fee_group.first.charge_filter_id

              result = ::Fees::ProjectionService.call(fees: filter_fee_group).raise_if_error!
              result.projected_amount_cents
            end
          elsif object.any? { |f| f.grouped_by.present? }
            grouped_fees = object.group_by(&:grouped_by).values
            grouped_fees.sum do |group_fee_list|
              ::Fees::ProjectionService.call(fees: group_fee_list).raise_if_error!.projected_amount_cents
            end
          else
            projection_result.projected_amount_cents
          end
        end

        private

        def projection_result
          @projection_result ||= ::Fees::ProjectionService.call(fees: object).raise_if_error!
        end
      end
    end
  end
end
