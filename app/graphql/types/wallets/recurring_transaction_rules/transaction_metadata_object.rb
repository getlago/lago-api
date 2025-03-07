# frozen_string_literal: true

module Types
  module Wallets
    module RecurringTransactionRules
      class TransactionMetadataObject < Types::BaseObject
        graphql_name "TransactionMetadata"

        field :key, String, null: false
        field :value, String, null: true
      end
    end
  end
end