# frozen_string_literal: true

module QuoteVersions
  module Validators
    # The deal currency is validated the same way whatever the order type: mandatory once the
    # version is approved, and always an ISO 4217 code when set.
    #
    # Expects the includer to expose `quote_version` and `scope`.
    module CurrencyValidation
      extend ActiveSupport::Concern

      # Currencies defines currency_list in its own included hook, so it exists only on a class that
      # includes Currencies itself, never as Currencies.currency_list. Pulling it in here means an
      # includer cannot forget it and lose the check to a NoMethodError.
      included do
        include Currencies
      end

      private

      def validate_currency
        currency = quote_version.currency

        if currency.blank?
          add_error(field: :currency, error_code: "value_is_mandatory") if scope == :approve
        elsif self.class.currency_list.exclude?(currency)
          add_error(field: :currency, error_code: "invalid_currency")
        end
      end
    end
  end
end
