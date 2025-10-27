# frozen_string_literal: true

module Wallets
  class ValidateService < BaseValidator
    MAXIMUM_WALLETS_PER_CUSTOMER = 1

    def valid?
      valid_customer?
      valid_paid_credits_amount? if args[:paid_credits]
      valid_granted_credits_amount? if args[:granted_credits]
      valid_expiration_at? if args[:expiration_at]
      valid_recurring_transaction_rules? if args[:recurring_transaction_rules].present?
      valid_metadata? if args[:transaction_metadata]
      valid_limitations? if args[:applies_to]
      valid_wallet_limit?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_wallet_limit?
      return true unless result.current_customer

      if result.current_customer.wallets.active.count >= MAXIMUM_WALLETS_PER_CUSTOMER
        return add_error(field: :customer, error_code: "wallet_limit_reached")
      end

      true
    end

    def valid_customer?
      result.current_customer = args[:customer]

      return add_error(field: :customer, error_code: "customer_not_found") unless result.current_customer

      true
    end

    def valid_paid_credits_amount?
      return true if ::Validators::DecimalAmountService.new(args[:paid_credits]).valid_amount?

      add_error(field: :paid_credits, error_code: "invalid_paid_credits")
      add_error(field: :paid_credits, error_code: "invalid_amount")
    end

    def valid_granted_credits_amount?
      return true if ::Validators::DecimalAmountService.new(args[:granted_credits]).valid_amount?

      add_error(field: :granted_credits, error_code: "invalid_granted_credits")
      add_error(field: :granted_credits, error_code: "invalid_amount")
    end

    def valid_expiration_at?
      return true if Validators::ExpirationDateValidator.valid?(args[:expiration_at])

      add_error(field: :expiration_at, error_code: "invalid_date")
      false
    end

    def valid_recurring_transaction_rules?
      if args[:recurring_transaction_rules].count > 1
        return add_error(field: :recurring_transaction_rules, error_code: "invalid_number_of_recurring_rules")
      end

      unless Wallets::RecurringTransactionRules::ValidateService.call(params: args[:recurring_transaction_rules].first)
        add_error(field: :recurring_transaction_rules, error_code: "invalid_recurring_rule")
      end
    end

    def valid_metadata?
      validator = ::Validators::MetadataValidator.new(args[:transaction_metadata])
      unless validator.valid?
        validator.errors.each do |field, error_code|
          add_error(field: field, error_code: error_code)
        end
        return false
      end

      true
    end

    def valid_limitations?
      limitation_result = BaseService::Result.new
      limitation_result.billable_metrics = result.billable_metrics
      limitation_result.billable_metric_identifiers = result.billable_metric_identifiers

      return true if Wallets::ValidateLimitationsService.new(limitation_result, **args).valid?

      add_error(field: :applies_to, error_code: "invalid_limitations")

      false
    end
  end
end
