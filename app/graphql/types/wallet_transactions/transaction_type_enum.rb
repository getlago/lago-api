# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module WalletTransactions
    class TransactionTypeEnum < Types::BaseEnum
      graphql_name "WalletTransactionTransactionTypeEnum"

      WalletTransaction::TRANSACTION_TYPES.each do |type|
        value type
      end
    end
  end
end
