# frozen_string_literal: true

module Queries
  class ContractWalletTransactionsQueryFiltersContract < Dry::Validation::Contract
    params do
      optional(:direction).maybe(:string, included_in?: CatalogWalletTransaction::DIRECTIONS.values)
      optional(:status).maybe(:string, included_in?: CatalogWalletTransaction::STATUSES.values)
      optional(:reason).maybe(:string, included_in?: CatalogWalletTransaction::REASONS.values)
      optional(:credit_allocation_code).maybe(:string)
    end
  end
end
