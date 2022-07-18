# frozen_string_literal: true

module Mutations
  module Wallets
    class Terminate < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'TerminateCustomerWallet'
      description 'Terminates a new Customer Wallet'

      argument :id, String, required: true

      type Types::Wallets::Object

      def resolve(**args)
        # Empty
      end
    end
  end
end
