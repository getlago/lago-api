# frozen_string_literal: true

module Charges
  module Validators
    class PackageService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_amount unless valid_amount?
        errors << :invalid_free_units unless valid_free_units?
        errors << :invalid_package_size unless valid_package_size?

        return result.fail!(code: :invalid_properties, message: errors) if errors.present?

        result
      end

      private

      def amount
        properties['amount']
      end

      def valid_amount?
        # NOTE: as we want to be the more precise with decimals, we only
        # accept amount that are in string to avoid float bad parsing
        # and use BigDecimal as a source of truth when computing amounts
        return false unless amount.is_a?(String)

        decimal_amount = BigDecimal(amount)

        decimal_amount.present? &&
          decimal_amount.finite? &&
          (decimal_amount.zero? || decimal_amount.positive?)
      # NOTE: If BigDecimal can't parse the amount, it will trigger
      # an ArgumentError is the type is not a numeric, ei: 'foo'
      # a TypeError is the amount is nil
      rescue ArgumentError, TypeError
        false
      end

      def package_size
        properties['package_size']
      end

      def valid_package_size?
        package_size.present? && package_size.is_a?(Integer) && package_size.positive?
      end

      def free_units
        properties['free_units']
      end

      def valid_free_units?
        free_units.present? && free_units.is_a?(Integer) && free_units >= 0
      end
    end
  end
end
