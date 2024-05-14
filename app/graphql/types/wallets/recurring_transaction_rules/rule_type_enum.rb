# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class RuleTypeEnum < Types::BaseEnum
        graphql_name 'RecurringTransactionRuleTypeEnum'

        RecurringTransactionRule::TRIGGERS.each do |type|
          value type
        end
      end
    end
  end
end
