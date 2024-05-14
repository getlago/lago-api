# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class UpdateInput < Types::BaseInputObject
        graphql_name 'UpdateRecurringTransactionRuleInput'

        argument :granted_credits, String, required: false
        argument :interval, Types::Wallets::RecurringTransactionRules::IntervalEnum, required: false
        argument :lago_id, ID, required: false
        argument :paid_credits, String, required: false
        argument :threshold_credits, String, required: false
        argument :trigger, Types::Wallets::RecurringTransactionRules::TriggerEnum, required: false
      end
    end
  end
end
