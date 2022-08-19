# frozen_string_literal: true

module Charges
  module ChargeModels
    class PercentageService < Charges::ChargeModels::BaseService
      protected

      def compute_amount
        compute_percentage_amount + compute_fixed_amount
      end

      def compute_percentage_amount
        return 0 if free_units_value > units

        (units - free_units_value) * rate.fdiv(100)
      end

      def compute_fixed_amount
        return 0 if units.zero?
        return 0 if fixed_amount.nil?

        (aggregation_result.count - free_units_count) * fixed_amount
      end

      def free_units_value
        return last_running_total unless last_running_total > free_units_per_total_aggregation

        free_units_per_total_aggregation.to_i
      end

      def free_units_count
        return free_units_per_events unless last_running_total > free_units_per_total_aggregation

        aggregation_result.options[:running_total].count { |e| e < free_units_per_total_aggregation }
      end

      def last_running_total
        @last_running_total ||= aggregation_result.options[:running_total].last
      end

      def free_units_per_total_aggregation
        @free_units_per_total_aggregation ||= BigDecimal(charge.properties['free_units_per_total_aggregation'] || 0)
      end

      def free_units_per_events
        @free_units_per_events ||= charge.properties['free_units_per_events'].to_i
      end

      # NOTE: FE divides percentage rate with 100 and sends to BE.
      def rate
        BigDecimal(charge.properties['rate'])
      end

      def fixed_amount
        @fixed_amount ||= BigDecimal(charge.properties['fixed_amount'] || 0)
      end
    end
  end
end
