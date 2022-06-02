# frozen_string_literal: true

module Charges
  module Validators
    class StandardService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_amount unless valid_amount?

        return result.fail!(:invalid_properties, errors) if errors.present?

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
    end
  end
end
