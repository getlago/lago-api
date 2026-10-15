# frozen_string_literal: true

module Resolvers
  class WalletResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    REQUIRED_PERMISSION = %w[customers:view wallets:create wallets:update wallets:top_up wallets:terminate]

    description "Query a single wallet of an organization"

    argument :id, ID, required: true, description: "Uniq ID of the wallet"

    type Types::Wallets::Object, null: true

    def resolve(id:)
      current_organization.wallets.find(id)
    rescue ActiveRecord::RecordNotFound
      not_found_error(resource: "wallet")
    end
  end
end
