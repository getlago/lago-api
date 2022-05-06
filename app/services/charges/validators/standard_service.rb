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

      def amount_cents
        properties['amount_cents']
      end

      def valid_amount?
        amount_cents.present? && amount_cents.is_a?(Integer) && amount_cents >= 0
      end
    end
  end
end
