# frozen_string_literal: true

module QuoteVersions
  module Validators
    class OneOffService < ::BaseValidator
      def initialize(result, quote_version:, scope:)
        @quote_version = quote_version
        @scope = scope

        super
      end

      def valid?
        structural = OneOff::StructuralService.new(billing_items:, scope:)

        if structural.valid?
          business = OneOff::BusinessService.new(quote_version:, billing_items:, scope:)
          business.valid?
          merge_errors(business.errors)
        else
          merge_errors(structural.errors)
        end

        if errors?
          result.validation_failure!(errors:)
          return false
        end

        true
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

      def merge_errors(layer_errors)
        layer_errors.each do |field, codes|
          codes.each { |code| add_error(field:, error_code: code) }
        end
      end
    end
  end
end
