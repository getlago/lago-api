# frozen_string_literal: true

module Charges
  module Validators
    class PercentageService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_rate unless valid_rate?
        errors << :invalid_fixed_amount unless valid_fixed_amount?

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
    end
  end
end
