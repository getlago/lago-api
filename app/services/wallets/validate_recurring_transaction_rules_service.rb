# frozen_string_literal: true

module Wallets
  class ValidateRecurringTransactionRulesService < BaseValidator
    def valid?
      return true unless args[:recurring_transaction_rules]

      valid_transaction_rules_number?
      valid_transaction_rules?

      if errors?
        result.validation_failure!(errors:)
        return false
      end

      true
    end

    private

    def valid_transaction_rules_number?
      return true if args[:recurring_transaction_rules].count.zero? || args[:recurring_transaction_rules].count == 1

      add_error(field: :recurring_transaction_rules, error_code: 'invalid_number_of_recurring_rules')
    end

    def valid_transaction_rules?
      return true if args[:recurring_transaction_rules].count.zero?

      rule = args[:recurring_transaction_rules].first
      trigger = rule[:trigger]&.to_s

      if !::Validators::DecimalAmountService.new(rule[:paid_credits]).valid_amount? ||
          !::Validators::DecimalAmountService.new(rule[:granted_credits]).valid_amount?

        add_error(field: :recurring_transaction_rules, error_code: 'invalid_recurring_rule')

        return
      end

      return true if trigger == 'interval' && RecurringTransactionRule.intervals.key?(rule[:interval])

      if trigger == 'threshold' && ::Validators::DecimalAmountService.new(rule[:threshold_credits]).valid_decimal?
        return true
      end

      add_error(field: :recurring_transaction_rules, error_code: 'invalid_recurring_rule')
    end
  end
end
