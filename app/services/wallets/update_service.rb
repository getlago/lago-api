# frozen_string_literal: true

module Wallets
  class UpdateService < BaseService
    def update(wallet:, args:)
      return result.not_found_failure!(resource: 'wallet') unless wallet
      return result unless valid_transaction_rules_number?(transaction_rules: args[:recurring_transaction_rules])
      return result unless valid_transaction_rules?(transaction_rules: args[:recurring_transaction_rules])

      ActiveRecord::Base.transaction do
        wallet.name = args[:name] if args.key?(:name)
        wallet.expiration_at = args[:expiration_at] if args.key?(:expiration_at)

        if args[:recurring_transaction_rules] && License.premium?
          Wallets::RecurringTransactionRules::UpdateService.call(wallet:, params: args[:recurring_transaction_rules])
        end

        wallet.save!
      end

      result.wallet = wallet
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def valid_transaction_rules_number?(transaction_rules:)
      return true if transaction_rules.nil? || transaction_rules.count.zero? || transaction_rules.count == 1

      add_invalid_number_of_recurring_rules_error

      false
    end

    def valid_transaction_rules?(transaction_rules:)
      return true if transaction_rules.nil? || transaction_rules.count.zero?

      rule = transaction_rules.first
      type = rule[:rule_type]&.to_s

      if !::Validators::DecimalAmountService.new(rule[:paid_credits]).valid_amount? ||
         !::Validators::DecimalAmountService.new(rule[:granted_credits]).valid_amount?

        add_invalid_recurring_rule_error

        return false
      end

      return true if type == 'interval' && RecurringTransactionRule.intervals.key?(rule[:interval])

      if type == 'threshold' && ::Validators::DecimalAmountService.new(rule[:threshold_credits]).valid_amount?
        return true
      end

      add_invalid_recurring_rule_error

      false
    end

    def add_invalid_recurring_rule_error
      result.single_validation_failure!(field: :recurring_transaction_rules, error_code: 'invalid_recurring_rule')
    end

    def add_invalid_number_of_recurring_rules_error
      result.single_validation_failure!(
        field: :recurring_transaction_rules,
        error_code: 'invalid_number_of_recurring_rules',
      )
    end
  end
end
