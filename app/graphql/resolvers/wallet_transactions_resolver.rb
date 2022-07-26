# frozen_string_literal: true

module Resolvers
  class WalletTransactionsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query wallet transactions'

    argument :ids, [ID], required: false, description: 'List of wallet transaction IDs to fetch'
    argument :wallet_id, ID, required: true, description: 'Uniq ID of the wallet'
    argument :page, Integer, required: false
    argument :limit, Integer, required: false
    argument :transaction_type, Types::WalletTransactions::TransactionTypeEnum, required: false
    argument :status, Types::WalletTransactions::StatusEnum, required: false

    type Types::WalletTransactions::Object.collection_type, null: false

    def resolve(
      wallet_id: nil,
      ids: nil,
      page: nil,
      limit: nil,
      status: nil,
      transaction_type: nil
    )
      validate_organization!

      current_wallet = Wallet.find(wallet_id)

      wallet_transactions = current_wallet
        .wallet_transactions
        .page(page)
        .limit(limit)

      wallet_transactions = wallet_transactions.where(transaction_type: transaction_type) if transaction_type.present?
      wallet_transactions = wallet_transactions.where(status: status) if status.present?
      wallet_transactions = wallet_transactions.where(id: ids) if ids.present?

      wallet_transactions
    rescue ActiveRecord::RecordNotFound
      not_found_error
    end
  end
end
