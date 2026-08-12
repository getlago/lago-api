# frozen_string_literal: true

module QuoteVersions
  module Validators
    # Runs the structural pass before the business one so DB lookups only ever see a payload
    # of the expected shape. Subclasses name the two passes for their order type.
    class BaseOrderTypeValidator < ::BaseValidator
      def initialize(result, quote_version:, scope:)
        @quote_version = quote_version
        @scope = scope

        super
      end

      def valid?
        return false unless structural_validator_class.new(result, billing_items:, scope:).valid?

        business_validator_class.new(result, quote_version:, billing_items:, scope:).valid?
      end

      private

      attr_reader :quote_version, :scope

      def structural_validator_class
        raise NotImplementedError, "#{self.class} must implement #structural_validator_class"
      end

      def business_validator_class
        raise NotImplementedError, "#{self.class} must implement #business_validator_class"
      end

      def billing_items
        @billing_items ||= normalized_billing_items
      end

      def normalized_billing_items
        items = quote_version.billing_items || {}

        if items.is_a?(Hash)
          items.deep_stringify_keys
        else
          items
        end
      end
    end
  end
end
