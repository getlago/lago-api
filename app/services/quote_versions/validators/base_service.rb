# frozen_string_literal: true

module QuoteVersions
  module Validators
    class BaseService < BaseValidator
      def initialize(result, quote_version:, scope: :approve)
        @quote_version = quote_version
        @scope = scope.to_sym
        super(result)
      end

      def valid?
        case quote_version.quote.order_type
        when "one_off"
          OneOffService.new(result, quote_version:, scope:).valid?
        else
          true
        end
      end

      protected

      attr_reader :quote_version, :scope
    end
  end
end
