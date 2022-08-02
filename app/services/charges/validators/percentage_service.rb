# frozen_string_literal: true

module Charges
  module Validators
    class PercentageService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_rate unless valid_rate?
        errors << :invalid_fixed_amount unless valid_fixed_amount?
        errors << :invalid_fixed_amount_target unless valid_fixed_amount_target?

        return result.fail!(code: :invalid_properties, message: errors) if errors.present?

        result
      end

      private

      def rate
        properties['rate']
      end

      def valid_rate?
        return false unless rate.is_a?(String)

        decimal_amount = BigDecimal(rate)

        decimal_amount.present? && decimal_amount.finite? && decimal_amount.positive?
      rescue ArgumentError, TypeError
        false
      end

      def fixed_amount
        properties['fixed_amount']
      end

      def valid_fixed_amount?
        return true if fixed_amount.nil? && fixed_amount_target.nil?

        return false unless fixed_amount.is_a?(String)

        decimal_amount = BigDecimal(fixed_amount)

        decimal_amount.present? &&
          decimal_amount.finite? &&
          (decimal_amount.zero? || decimal_amount.positive?)
      rescue ArgumentError, TypeError
        false
      end

      def fixed_amount_target
        properties['fixed_amount_target']
      end

      def valid_fixed_amount_target?
        return true if fixed_amount.nil? && fixed_amount_target.nil?

        fixed_amount_target.present? &&
          fixed_amount_target.is_a?(String) &&
          Charge::FIXED_AMOUNT_TARGETS.include?(fixed_amount_target)
      end
    end
  end
end
