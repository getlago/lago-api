# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module Wallets
    module RecurringTransactionRules
      class TransactionMetadataObject < Types::BaseObject
        graphql_name "TransactionMetadata"

        field :key, String, null: false
        field :value, String, null: false
      end
    end
  end
end
