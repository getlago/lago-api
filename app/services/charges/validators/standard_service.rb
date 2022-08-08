# frozen_string_literal: true

module Charges
  module Validators
    class StandardService < Charges::Validators::BaseService
      def validate
        errors = []
        errors << :invalid_amount unless valid_amount?

        return result.fail!(code: :invalid_properties, message: errors) if errors.present?

        result
      end

      private

      def amount
        properties['amount']
      end

      def valid_amount?
        ::Validators::DecimalAmountService.new(amount).valid_amount?
      end
    end
  end
end
