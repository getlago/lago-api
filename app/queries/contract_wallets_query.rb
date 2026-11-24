# frozen_string_literal: true

class ContractWalletsQuery < BaseQuery
  Result = BaseResult[:contract_wallets]
  Filters = BaseFilters[:contract_id, :created_at_from, :created_at_to]

  def call
    contract_wallets = CatalogWallet.where(organization:)
    contract_wallets = contract_wallets.where(contract_id: filters.contract_id) if filters.contract_id.present?
    contract_wallets = with_date_range(contract_wallets, :created_at)
    contract_wallets = apply_consistent_ordering(contract_wallets)

    result.contract_wallets = paginate(contract_wallets)
    result
  rescue BaseService::FailedResult
    result
  end
end
