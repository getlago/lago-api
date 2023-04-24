# frozen_string_literal: true

module WalletTransactions
  class ValidateService < BaseValidator
    def valid?
      valid_wallet?
      valid_paid_credits_amount? if args[:paid_credits]
      valid_granted_credits_amount? if args[:granted_credits]

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_wallet?
      organization = Organization.find_by(id: args[:organization_id])

      result.current_wallet = organization.wallets.find_by(id: args[:wallet_id])

      return add_error(field: :wallet_id, error_code: 'wallet_not_found') unless result.current_wallet
      return add_error(field: :wallet_id, error_code: 'wallet_is_terminated') if result.current_wallet.terminated?

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
