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
        return 0 if free_units_count >= aggregation_result.count

        (aggregation_result.count - free_units_count) * fixed_amount
      end

      def free_units_value
        return 0 if last_running_total.zero?
        return last_running_total if free_units_per_total_aggregation.zero?
        return last_running_total if last_running_total <= free_units_per_total_aggregation

        free_units_per_total_aggregation
      end

      def free_units_count
        [
          free_units_per_events,
          aggregation_result.options[:running_total]&.count { |e| e < free_units_per_total_aggregation } || 0,
        ].excluding(0).min || 0
      end

      def last_running_total
        @last_running_total ||= aggregation_result.options[:running_total]&.last || 0
      end

      def free_units_per_total_aggregation
        @free_units_per_total_aggregation ||= BigDecimal(properties['free_units_per_total_aggregation'] || 0)
      end

      def free_units_per_events
        @free_units_per_events ||= properties['free_units_per_events'].to_i
      end

      # NOTE: FE divides percentage rate with 100 and sends to BE.
      def rate
        BigDecimal(properties['rate'])
      end

      def fixed_amount
        @fixed_amount ||= BigDecimal(properties['fixed_amount'] || 0)
      end
    end
  end
end
