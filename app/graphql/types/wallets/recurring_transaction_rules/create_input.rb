# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class CreateInput < Types::BaseInputObject
        graphql_name 'CreateRecurringTransactionRuleInput'

        argument :interval, Types::Wallets::RecurringTransactionRules::IntervalEnum, required: false
        argument :threshold_credits, String, required: false
        argument :trigger, Types::Wallets::RecurringTransactionRules::TriggerEnum, required: true
      end
    end
  end
end
