# frozen_string_literal: true

module Wallets
  class ValidateService < BaseValidator
    def valid?
      valid_customer?
      valid_paid_credits_amount? if args[:paid_credits]
      valid_granted_credits_amount? if args[:granted_credits]
      valid_expiration_at? if args[:expiration_at]
      valid_recurring_transaction_rules? if args[:recurring_transaction_rules]

      if errors?
        result.validation_failure!(errors:)
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

    def valid_expiration_at?
      return true if args[:expiration_at].blank?

      future = Utils::Datetime.valid_format?(args[:expiration_at]) && expiration_at.to_date > Time.current.to_date
      return true if future

      add_error(field: :expiration_at, error_code: 'invalid_date')

      false
    end

    def expiration_at
      @expiration_at ||= if args[:expiration_at].is_a?(String)
        DateTime.strptime(args[:expiration_at])
      else
        args[:expiration_at]
      end
    end

    def valid_recurring_transaction_rules?
      if args[:recurring_transaction_rules].count != 1
        return add_error(field: :recurring_transaction_rules, error_code: 'invalid_number_of_recurring_rules')
      end

      recurring_rule = args[:recurring_transaction_rules].first

      if recurring_rule[:rule_type]&.to_s == 'interval' &&
          RecurringTransactionRule.intervals.key?(recurring_rule[:interval])

        return true
      end

      if recurring_rule[:rule_type]&.to_s == 'threshold' &&
          ::Validators::DecimalAmountService.new(recurring_rule[:threshold_credits]).valid_decimal?

        return true
      end

      add_error(field: :recurring_transaction_rules, error_code: 'invalid_recurring_rule')
    end
  end
end
