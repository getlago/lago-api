# frozen_string_literal: true

class ContractWalletTransactionsQuery < BaseQuery
  Result = BaseResult[:wallet_transactions]
  Filters = BaseFilters[:contract_wallet_id, :direction, :status, :reason, :credit_allocation_code, :created_at_from, :created_at_to]

  def call
    validate_filters
    return result if result.error.present?

    wallet_transactions = CatalogWalletTransaction.where(organization:)
    wallet_transactions = wallet_transactions.where(catalog_wallet_id: filters.contract_wallet_id) if filters.contract_wallet_id.present?
    wallet_transactions = wallet_transactions.where(direction: filters.direction) if filters.direction.present?
    wallet_transactions = wallet_transactions.where(status: filters.status) if filters.status.present?
    wallet_transactions = wallet_transactions.where(reason: filters.reason) if filters.reason.present?
    wallet_transactions = with_credit_allocation_code(wallet_transactions) if filters.credit_allocation_code.present?
    wallet_transactions = with_date_range(wallet_transactions, :created_at)
    wallet_transactions = apply_consistent_ordering(wallet_transactions)

    result.wallet_transactions = paginate(wallet_transactions)
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::ContractWalletTransactionsQueryFiltersContract.new
  end

  # Removed ones too: a wallet keeps the transactions of a credit allocation after its removal, and its code
  # can then be given to another one.
  def with_credit_allocation_code(scope)
    credit_allocations = CatalogWalletCreditAllocation.with_discarded.where(organization:, code: filters.credit_allocation_code)

    scope.where(credit_allocation_id: credit_allocations.select(:id))
  end
end
