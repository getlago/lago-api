# frozen_string_literal: true

module Clock
  class TerminateRecurringTransactionRulesJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_CLOCK"])
        :clock_worker
      else
        :clock
      end
    end

    def perform
      RecurringTransactionRule.expired.find_each do |recurring_transaction_rule|
        puts recurring_transaction_rule.inspect
      end
    end
  end
end
