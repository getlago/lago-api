# frozen_string_literal: true

module QuoteVersions
  module Validators
    class SubscriptionCreationValidator < BaseOrderTypeValidator
      private

      def structural_validator_class
        SubscriptionCreation::StructuralValidator
      end

      def business_validator_class
        SubscriptionCreation::BusinessValidator
      end
    end
  end
end
