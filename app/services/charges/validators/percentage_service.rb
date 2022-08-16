# frozen_string_literal: true

module Charges
  module Validators
    class PercentageService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_rate unless valid_rate?
        errors << :invalid_fixed_amount unless valid_fixed_amount?
        errors << :invalid_free_units_per_events unless valid_free_units_per_events?
        errors << :invalid_free_units_per_total_aggregation unless valid_free_units_per_total_aggregation?

        return result.fail!(code: :invalid_properties, message: errors) if errors.present?

        result
      end

      private

      def rate
        properties['rate']
      end

      def valid_rate?
        ::Validators::DecimalAmountService.new(rate).valid_positive_amount?
      end

      def fixed_amount
        properties['fixed_amount']
      end

      def valid_fixed_amount?
        return true if fixed_amount.nil?

        ::Validators::DecimalAmountService.new(fixed_amount).valid_amount?
      end

      def free_units_per_events
        properties['free_units_per_events']
      end

      def valid_free_units_per_events?
        return true if free_units_per_events.nil?

        free_units_per_events.is_a?(Integer) && free_units_per_events.positive?
      end

      def free_units_per_total_aggregation
        properties['free_units_per_total_aggregation']
      end

      def valid_free_units_per_total_aggregation?
        return true if free_units_per_total_aggregation.nil?

        ::Validators::DecimalAmountService.new(free_units_per_total_aggregation).valid_amount?
      end
    end
  end
end
