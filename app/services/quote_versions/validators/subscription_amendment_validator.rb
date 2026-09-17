# frozen_string_literal: true

module QuoteVersions
  module Validators
    # An amendment carries a subscription_creation payload, so its schema is reused as is. What an
    # amendment constrains on top of it is business state, see SubscriptionAmendment::BusinessValidator.
    class SubscriptionAmendmentValidator < BaseOrderTypeValidator
      private

      def structural_validator_class
        SubscriptionCreation::StructuralValidator
      end

      def business_validator_class
        SubscriptionAmendment::BusinessValidator
      end
    end
  end
end
