# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class CreateInput < Types::BaseInputObject
        graphql_name 'CreateRecurringTransactionRuleInput'

        argument :interval, Types::Wallets::RecurringTransactionRules::IntervalEnum, required: false
        argument :rule_type, Types::Wallets::RecurringTransactionRules::RuleTypeEnum, required: true
        argument :threshold_credits, String, required: false
      end
    end
  end
end
