# frozen_string_literal: true

module WalletTransactions
  class ValidateService
    def initialize(result, **args)
      @result = result
      @args = args
    end

    def valid?
      errors = []
      errors << valid_wallet?
      errors << valid_paid_credits_amount?
      errors << valid_granted_credits_amount?
      errors = errors.compact

      unless errors.empty?
        result.fail!(
          code: 'unprocessable_entity',
          message: 'Validation error on the record',
          details: errors,
        )
        return false
      end

      true
    end

    private

    attr_accessor :result, :args

    def valid_wallet?
      current_wallet = Wallet.find_by(
        id: args[:wallet_id],
        customer_id: args[:customer_id],
      )

      return 'wallet_not_found' unless current_wallet

      'wallet_is_terminated' if current_wallet.terminated?
    end

    def valid_paid_credits_amount?
      'invalid_paid_credits' unless ::Validators::DecimalAmountService.new(args[:paid_credits]).valid_amount?
    end

    def valid_granted_credits_amount?
      unless ::Validators::DecimalAmountService.new(args[:granted_credits]).valid_amount?
        'invalid_granted_credits'
      end
    end
  end
end
