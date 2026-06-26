# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Queries
  class WalletTransactionConsumptionsQueryFiltersContract < Dry::Validation::Contract
    params do
      required(:wallet_transaction_id).filled(:string)
      required(:direction).filled(:"coercible.string", included_in?: %w[consumptions fundings])
    end
  end
end
