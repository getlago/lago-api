# frozen_string_literal: true

class WalletTransactionsQuery < BaseQuery
  def call(wallet_id:, page:, limit:, filters: {})
    wallet_transactions = base_scope(wallet_id:)

    if valid_transaction_type?(filters[:transaction_type])
      wallet_transactions = wallet_transactions.where(transaction_type: filters[:transaction_type])
    end
    wallet_transactions = wallet_transactions.where(id: filters[:ids]) if filters[:ids].present?
    wallet_transactions = wallet_transactions.where(status: filters[:status]) if valid_status?(filters[:status])
    wallet_transactions = wallet_transactions.order(created_at: :desc).page(page).per(limit)

    result.wallet_transactions = wallet_transactions
    result
  end

  private

  def base_scope(wallet_id:)
    Wallet.find(wallet_id).wallet_transactions
  end

  def valid_status?(status)
    WalletTransaction.statuses.key?(status)
  end

  def valid_transaction_type?(transaction_type)
    WalletTransaction.transaction_types.key?(transaction_type)
  end
end
