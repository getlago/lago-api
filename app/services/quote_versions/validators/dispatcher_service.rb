# frozen_string_literal: true

module QuoteVersions
  module Validators
    class DispatcherService < BaseValidator
      def initialize(result, quote_version:, scope: :approve)
        @quote_version = quote_version
        @scope = scope.to_sym
        super(result)
      end

      def valid?
        case quote_version.quote.order_type
        when "one_off"
          OneOffService.new(result, quote_version:, scope:).valid?
        when "subscription_creation", "subscription_amendment"
          true
        else
          result.validation_failure!(errors: {order_type: ["unsupported_order_type"]})
          false
        end
      end

      private

      attr_reader :quote_version, :scope
    end
  end
end
