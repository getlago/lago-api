# frozen_string_literal: true

module Wallets
  class ValidateX402Service < BaseValidator
    CURRENCY = "USD"

    def valid?
      if enabling?
        valid_currency?
        valid_wallet_refresh?
        valid_recurring_transaction_rules_on_enable?
      elsif x402_enabled_after_update?
        valid_recurring_transaction_rules_on_x402_wallet?
      end

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def wallet
      args[:wallet]
    end

    def enabling?
      x402_enabled_after_update? && !wallet.x402_enabled
    end

    def x402_enabled_after_update?
      requested = ActiveModel::Type::Boolean.new.cast(args[:x402_enabled])

      if requested.nil?
        wallet.x402_enabled
      else
        requested
      end
    end

    def valid_currency?
      if wallet.currency == CURRENCY
        true
      else
        add_error(field: :x402_enabled, error_code: "currency_not_supported")
      end
    end

    def valid_wallet_refresh?
      if ENV["LAGO_REDIS_CACHE_URL"].present? && ENV["LAGO_DISABLE_WALLET_REFRESH"] != "true"
        true
      else
        add_error(field: :x402_enabled, error_code: "wallet_refresh_unavailable")
      end
    end

    def valid_recurring_transaction_rules_on_enable?
      if recurring_transaction_rules_after_update?
        add_error(field: :x402_enabled, error_code: "recurring_transaction_rules_not_supported")
      else
        true
      end
    end

    def valid_recurring_transaction_rules_on_x402_wallet?
      if args[:recurring_transaction_rules].present?
        add_error(field: :recurring_transaction_rules, error_code: "not_supported_for_x402_wallet")
      else
        true
      end
    end

    def recurring_transaction_rules_after_update?
      if args[:recurring_transaction_rules].nil?
        wallet.recurring_transaction_rules.active.exists?
      else
        args[:recurring_transaction_rules].present?
      end
    end
  end
end
