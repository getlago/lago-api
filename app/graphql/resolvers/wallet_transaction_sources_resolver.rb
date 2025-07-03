# frozen_string_literal: true

module Resolvers
  class WalletTransactionSourcesResolver < Resolvers::BaseResolver
    include AuthenticableApiUser
    include RequiredOrganization

    description "Query wallet transaction sources"

    type [Types::WalletTransactions::SourceEnum], null: false

    def resolve
      WalletTransaction::SOURCES
    end
  end
end 