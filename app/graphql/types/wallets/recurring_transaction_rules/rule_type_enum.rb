# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class RuleTypeEnum < Types::BaseEnum
        graphql_name 'RecurringTransactionRuleTypeEnum'

        RecurringTransactionRule::RULE_TYPES.each do |type|
          value type
        end
      end
    end
  end
end
