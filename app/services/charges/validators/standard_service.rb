# frozen_string_literal: true

module Charges
  module Validators
    class StandardService < Charges::Validators::BaseService
      def valid?
        validate_amount

        super
      end

      private

      def amount
        properties['amount']
      end

      def validate_amount
        return if ::Validators::DecimalAmountService.new(amount).valid_amount?

        add_error(field: :amount, error_code: 'invalid_amount')
      end

      def validate_grouped_by
        return if grouped_by.blank?
        return if grouped_by.is_a?(Array) && grouped_by.all? { |f| f.is_a?(String) }

        add_error(field: :grouped_by, error_code: 'invalid_grouped_by')
      end
    end
  end
end
