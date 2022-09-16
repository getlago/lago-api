# frozen_string_literal: true

module Wallets
  class ValidateService < BaseValidator
    def valid?
      valid_customer?
      valid_paid_credits_amount? if args[:paid_credits]
      valid_granted_credits_amount? if args[:granted_credits]

      if errors?
        result.validation_failure!(errors: errors)
        return false
      end

      true
    end

    private

    def valid_customer?
      result.current_customer = args[:customer]

      return add_error(field: :customer, error_code: 'customer_not_found') unless result.current_customer

      if result.current_customer.wallets.active.exists?
        return add_error(
          field: :customer,
          error_code: 'wallet_already_exists',
        )
      end

      true
    end

    def valid_paid_credits_amount?
      return true if ::Validators::DecimalAmountService.new(args[:paid_credits]).valid_amount?

      add_error(field: :paid_credits, error_code: 'invalid_paid_credits')
    end

    def valid_granted_credits_amount?
      return true if ::Validators::DecimalAmountService.new(args[:granted_credits]).valid_amount?

      add_error(field: :granted_credits, error_code: 'invalid_granted_credits')
    end
  end
end
