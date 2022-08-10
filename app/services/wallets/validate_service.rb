# frozen_string_literal: true

module Wallets
  class ValidateService
    def initialize(result, **args)
      @result = result
      @args = args
    end

    def valid?
      errors = []
      errors << valid_customer?
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

    def valid_customer?
      current_customer = Customer.find_by(
        id: args[:customer_id],
        organization_id: args[:organization_id],
      )

      return 'customer_not_found' unless current_customer
      return 'wallet_already_exists' if current_customer.wallets.active.exists?
      return 'no_active_subscription' unless current_customer.subscriptions.active.exists?
    end

    def valid_paid_credits_amount?
      return 'invalid_paid_credits' unless ::Validators::DecimalAmountService.new(args[:paid_credits]).valid_amount?
    end

    def valid_granted_credits_amount?
      unless ::Validators::DecimalAmountService.new(args[:granted_credits]).valid_amount?
        'invalid_granted_credits'
      end
    end
  end
end
