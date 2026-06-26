# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Charges
  module Validators
    class StandardService < Charges::Validators::BaseService
      def valid?
        validate_amount

        super
      end

      private

      def amount
        properties["amount"]
      end

      def validate_amount
        return if ::Validators::DecimalAmountService.new(amount).valid_amount?

        add_error(field: :amount, error_code: "invalid_amount")
      end
    end
  end
end
