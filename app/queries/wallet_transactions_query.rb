# frozen_string_literal: true

class WalletTransactionsQuery < BaseQuery
  def initialize(organization:, wallet_id:, pagination: DEFAULT_PAGINATION_PARAMS, filters: {}, search_term: nil, order: nil)
    @wallet = organization.wallets.find_by(id: wallet_id)
    super(organization:, pagination:, filters:, search_term:, order:)
  end

  def call
    return result.not_found_failure!(resource: 'wallet') unless wallet

    wallet_transactions = wallet.wallet_transactions
    wallet_transactions = paginate(wallet_transactions)
    wallet_transactions = apply_consistent_ordering(wallet_transactions)

    if valid_transaction_type?(filters.transaction_type)
      wallet_transactions = with_transaction_type(wallet_transactions)
    end

    wallet_transactions = with_status(wallet_transactions) if valid_status?(filters.status)

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

  def valid_status?(status)
    WalletTransaction.statuses.key?(status)
  end

  def valid_transaction_type?(transaction_type)
    WalletTransaction.transaction_types.key?(transaction_type)
  end
end
