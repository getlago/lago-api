# frozen_string_literal: true

class WalletTransactionsQuery < BaseQuery
  Result = BaseResult[:wallet_transactions]
  Filters = BaseFilters[:transaction_type, :status, :transaction_status, :metadata]

  def initialize(organization:, wallet_id:, pagination: DEFAULT_PAGINATION_PARAMS, filters: {}, search_term: nil, order: nil)
    @wallet = organization.wallets.find_by(id: wallet_id)
    super(organization:, pagination:, filters:, search_term:, order:)
  end

  def call
    return result.not_found_failure!(resource: "wallet") unless wallet

    wallet_transactions = wallet.wallet_transactions
    wallet_transactions = paginate(wallet_transactions)
    wallet_transactions = apply_consistent_ordering(wallet_transactions)

    if valid_transaction_type?(filters.transaction_type)
      wallet_transactions = with_transaction_type(wallet_transactions)
    end

    wallet_transactions = with_status(wallet_transactions) if valid_status?(filters.status)

    if valid_transaction_status?(filters.transaction_status)
      wallet_transactions = with_transaction_status(wallet_transactions)
    end

    wallet_transactions = with_metadata(wallet_transactions) if filters.metadata.is_a?(Hash) && filters.metadata.present?

    result.wallet_transactions = wallet_transactions
    result
  end

  private

  attr_reader :wallet

  def with_transaction_type(scope)
    scope.where(transaction_type: filters.transaction_type)
  end

  def with_status(scope)
    scope.where(status: filters.status)
  end

  def with_transaction_status(scope)
    scope.where(transaction_status: filters.transaction_status)
  end

  def with_metadata(scope)
    filters.metadata.reduce(scope) do |relation, (key, value)|
      next relation if value.blank?

      relation.where(
        "EXISTS (SELECT 1 FROM jsonb_array_elements(wallet_transactions.metadata) AS pair " \
        "WHERE pair->>'key' = ? AND pair->>'value' = ?)",
        key.to_s, value.to_s
      )
    end
  end

  def valid_status?(status)
    WalletTransaction.statuses.key?(status)
  end

  def valid_transaction_type?(transaction_type)
    WalletTransaction.transaction_types.key?(transaction_type)
  end

  def valid_transaction_status?(transaction_status)
    WalletTransaction.transaction_statuses.key?(transaction_status)
  end
end
