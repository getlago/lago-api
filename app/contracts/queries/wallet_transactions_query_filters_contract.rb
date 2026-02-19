# frozen_string_literal: true

module Queries
  class WalletTransactionsQueryFiltersContract < Dry::Validation::Contract
    params do
      required(:wallet_id).filled(:string)

      optional(:transaction_type).maybe do
        value(:string, included_in?: WalletTransaction.transaction_types.keys.map(&:to_s)) |
          array(:string, included_in?: WalletTransaction.transaction_types.keys.map(&:to_s))
      end

      optional(:transaction_status).maybe do
        value(:string, included_in?: WalletTransaction.transaction_statuses.keys.map(&:to_s)) |
          array(:string, included_in?: WalletTransaction.transaction_statuses.keys.map(&:to_s))
      end

      optional(:status).maybe do
        value(:string, included_in?: WalletTransaction.statuses.keys.map(&:to_s)) |
          array(:string, included_in?: WalletTransaction.statuses.keys.map(&:to_s))
      end
    end
  end
end
