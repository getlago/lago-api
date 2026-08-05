# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OneOffValidator < ::BaseValidator
      def initialize(result, quote_version:, scope:)
        @quote_version = quote_version
        @scope = scope

        super
      end

      def valid?
        structural = OneOff::StructuralValidator.new(result, billing_items:, scope:)
        return false unless structural.valid?

        OneOff::BusinessValidator.new(result, quote_version:, billing_items:, scope:).valid?
      end

      private

      attr_reader :quote_version, :scope

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
