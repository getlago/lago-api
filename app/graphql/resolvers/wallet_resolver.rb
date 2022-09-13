# frozen_string_literal: true

module Resolvers
  class WalletResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description 'Query a single wallet'

    argument :id, ID, required: true, description: 'Uniq ID of the wallet'

    type Types::Wallets::SingleObject, null: true

    def resolve(id: nil)
      validate_organization!

      Wallet.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: 'wallet')
    end
  end
end
