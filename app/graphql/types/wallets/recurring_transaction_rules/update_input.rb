# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class UpdateInput < Types::BaseInputObject
        graphql_name 'UpdateRecurringTransactionRuleInput'

        argument :granted_credits, String, required: false
        argument :interval, Types::Wallets::RecurringTransactionRules::IntervalEnum, required: false
        argument :invoice_requires_successful_payment, Boolean, required: false
        argument :lago_id, ID, required: false
        argument :method, Types::Wallets::RecurringTransactionRules::MethodEnum, required: false
        argument :paid_credits, String, required: false
        argument :started_at, GraphQL::Types::ISO8601DateTime, required: false
        argument :target_ongoing_balance, String, required: false
        argument :threshold_credits, String, required: false
        argument :trigger, Types::Wallets::RecurringTransactionRules::TriggerEnum, required: false
      end
    end
  end
end
