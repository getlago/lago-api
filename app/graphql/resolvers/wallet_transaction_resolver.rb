# frozen_string_literal: true

module Resolvers
  class WalletTransactionResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single wallet transaction'

    argument :id, ID, required: true, description: 'Uniq ID of the wallet transaction'

    type Types::WalletTransactions::SingleObject, null: true

    def resolve(id: nil)
      validate_organization!

      current_organization.wallet_transactions.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'wallet_transaction')
    end
  end
end
