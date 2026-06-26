# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module WalletTransactions
    class MetadataObject < Types::BaseObject
      graphql_name "WalletTransactionMetadataObject"

      field :key, String, null: false
      field :value, String, null: false
    end
  end
end
