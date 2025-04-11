# frozen_string_literal: true

module Clock
  class TerminateRecurringTransactionRulesJob < ClockJob
    def perform
      RecurringTransactionRule.eligible_for_termination.find_each do |recurring_transaction_rule|
        Wallets::RecurringTransactionRules::TerminateService.call(recurring_transaction_rule:)
      end
    end
  end
end
