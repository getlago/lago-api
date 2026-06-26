# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module WalletTransactions
    class MetadataInput < Types::BaseInputObject
      graphql_name "WalletTransactionMetadataInput"

      argument :key, String, required: true
      argument :value, String, required: true
    end
  end
end
