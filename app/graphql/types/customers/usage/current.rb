# frozen_string_literal: true

module Types
  module Customers
    module Usage
      class Current < Types::BaseObject
        graphql_name "CustomerUsage"

        field :from_datetime, GraphQL::Types::ISO8601DateTime, null: false
        field :to_datetime, GraphQL::Types::ISO8601DateTime, null: false

        field :currency, Types::CurrencyEnum, null: false
        field :issuing_date, GraphQL::Types::ISO8601Date, null: false

        field :amount_cents, GraphQL::Types::BigInt, null: false
        field :projected_amount_cents, GraphQL::Types::BigInt, null: false
        field :taxes_amount_cents, GraphQL::Types::BigInt, null: false
        field :total_amount_cents, GraphQL::Types::BigInt, null: false

        field :charges_usage, [Types::Customers::Usage::Charge], null: false

        def charges_usage
          object.fees.group_by(&:charge_id).values
        end

        def projected_amount_cents # rubocop:disable GraphQL/ResolverMethodLength
          fee_groups = object.fees.group_by(&:charge_id).values

          fee_groups.sum do |fee_group|
            charge = fee_group.first.charge
            charge_has_grouping = fee_group.any? { |f| f.grouped_by.present? }

            if charge.filters.any?
              defined_filter_fees = fee_group.select(&:charge_filter_id)
              defined_filter_fees.sum do |fee|
                ::Fees::ProjectionService.call(fees: [fee]).raise_if_error!.projected_amount_cents
              end
            elsif charge_has_grouping
              groups = fee_group.group_by(&:grouped_by).values
              groups.sum do |single_group_fees|
                ::Fees::ProjectionService.call(fees: single_group_fees).raise_if_error!.projected_amount_cents
              end
            else
              ::Fees::ProjectionService.call(fees: fee_group).raise_if_error!.projected_amount_cents
            end
          end
        end
      end
    end
  end
end
