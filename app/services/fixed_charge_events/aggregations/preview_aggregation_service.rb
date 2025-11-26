# frozen_string_literal: true

module FixedChargeEvents
  module Aggregations
    class PreviewAggregationService < BaseService
      def call
        units = if fixed_charge.prorated?
          calculate_prorated_units
        else
          fixed_charge.units
        end

        result.aggregation = units
        result.full_units_number = fixed_charge.units
        result
      end

      private

      def calculate_prorated_units
        from_date = from_datetime.to_date
        to_date = to_datetime.to_date

        billing_period_days = (to_date - from_date).to_i + 1
        full_period_days = charges_duration || billing_period_days

        return fixed_charge.units if billing_period_days >= full_period_days

        # Prorate units based on the ratio of billing period to full period
        fixed_charge.units * (billing_period_days.to_f / full_period_days)
      end
    end
  end
end
