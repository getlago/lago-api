# frozen_string_literal: true

class WalletTransactionsQuery < BaseQuery
  Result = BaseResult[:wallet_transactions]
  Filters = BaseFilters[:wallet_id, :transaction_type, :status, :transaction_status]

  def call
    return result unless validate_filters.success?
    return result.not_found_failure!(resource: "wallet") unless wallet

    wallet_transactions = wallet.wallet_transactions
    wallet_transactions = paginate(wallet_transactions)
    wallet_transactions = apply_consistent_ordering(wallet_transactions)

    wallet_transactions = with_transaction_type(wallet_transactions) if filters.transaction_type.present?
    wallet_transactions = with_transaction_status(wallet_transactions) if filters.transaction_status.present?
    wallet_transactions = with_status(wallet_transactions) if filters.status.present?

    result.wallet_transactions = wallet_transactions
    result
  rescue BaseService::FailedResult
    result
  end

  private

  def filters_contract
    @filters_contract ||= Queries::WalletTransactionsQueryFiltersContract.new
  end

  def wallet
    @wallet ||= organization.wallets.find_by(id: filters.wallet_id)
  end

  def with_transaction_type(scope)
    scope.where(transaction_type: filters.transaction_type)
  end

  def with_transaction_status(scope)
    scope.where(transaction_status: filters.transaction_status)
  end

  def with_status(scope)
    scope.where(status: filters.status)
  end
end
