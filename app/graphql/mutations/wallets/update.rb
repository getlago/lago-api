# frozen_string_literal: true

module Mutations
  module Wallets
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'UpdateCustomerWallet'
      description 'Updates a new Customer Wallet'

      argument :id, String, required: true
      argument :expiration_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Wallets::Object

      def resolve(**args)
        # Empty
      end
    end
  end
end
