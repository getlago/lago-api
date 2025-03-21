# frozen_string_literal: true

module Clock
  class TerminateRecurringTransactionRulesJob < ApplicationJob
    if ENV["SENTRY_DSN"].present? && ENV["SENTRY_ENABLE_CRONS"].present?
      include SentryCronConcern
    end

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      RecurringTransactionRule.eligible_for_termination.find_each do |recurring_transaction_rule|
        Wallets::RecurringTransactionRules::TerminateService.call(recurring_transaction_rule:)
      end
    end
  end
end
