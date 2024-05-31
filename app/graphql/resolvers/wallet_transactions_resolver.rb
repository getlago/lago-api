# frozen_string_literal: true

module Resolvers
  class WalletTransactionsResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query wallet transactions'

    argument :ids, [ID], required: false, description: 'List of wallet transaction IDs to fetch'
    argument :limit, Integer, required: false
    argument :page, Integer, required: false
    argument :status, Types::WalletTransactions::StatusEnum, required: false
    argument :transaction_type, Types::WalletTransactions::TransactionTypeEnum, required: false
    argument :wallet_id, ID, required: true, description: 'Uniq ID of the wallet'

    type Types::WalletTransactions::Object.collection_type, null: false

    def resolve(
      wallet_id: nil,
      ids: nil,
      page: nil,
      limit: nil,
      status: nil,
      transaction_type: nil
    )
      query = WalletTransactionsQuery.new(organization: current_organization)
      result = query.call(
        wallet_id:,
        page:,
        limit:,
        filters: {
          ids:,
          status:,
          transaction_type:
        }
      )

      return result_error(result) unless result.success?

      result.wallet_transactions
    end
  end
end
