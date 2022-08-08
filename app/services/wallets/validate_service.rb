# frozen_string_literal: true

module Wallets
  class ValidateService
    def initialize(result, **args)
      @result = result
      @args = args
    end

    def valid?
      return false unless valid_customer?
      return false unless valid_paid_credits_amount?
      return false unless valid_granted_credits_amount?

      true
    end

    private

    attr_accessor :result, :args

    def valid_customer?
      current_customer = Customer.find_by(
        id: args[:customer_id],
        organization_id: args[:organization_id],
      )

      unless current_customer
        result = result.fail!(code: 'missing_argument', message: 'unable to find customer')
        return false
      end

      if current_customer.wallets.active.any?
        result = result.fail!(code: 'wallet_already_exists', message: 'a wallet already exists for this customer')
        return false
      end

      unless current_customer.subscriptions.active.any?
        result = result.fail!(code: 'no_active_subscription', message: 'customer does not have any active subscription')
        return false
      end

      true
    end

    def valid_paid_credits_amount?
      return true if args[:paid_credits].nil?

      unless ::Validators::DecimalAmountService.new(args[:paid_credits]).valid_amount?
        result.fail!(code: 'invalid_paid_credits', message: 'invalid paid credits amount')
        return false
      end

      true
    end

    def valid_granted_credits_amount?
      return true if args[:granted_credits].nil?

      unless ::Validators::DecimalAmountService.new(args[:granted_credits]).valid_amount?
        result.fail!(code: 'invalid_granted_credits', message: 'invalid granted credits amount')
        return false
      end

      true
    end
  end
end
