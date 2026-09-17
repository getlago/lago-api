# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OneOffValidator < BaseOrderTypeValidator
      private

      def structural_validator_class
        OneOff::StructuralValidator
      end

      def business_validator_class
        OneOff::BusinessValidator
      end
    end
  end
end
