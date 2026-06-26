# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Wallets
    module RecurringTransactionRules
      class MethodEnum < Types::BaseEnum
        graphql_name "RecurringTransactionMethodEnum"

        RecurringTransactionRule::METHODS.each do |type|
          value type
        end
      end
    end
  end
end
