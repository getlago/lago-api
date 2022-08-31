# frozen_string_literal: true

module Mutations
  module WalletTransactions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCustomerWalletTransaction'
      description 'Creates a new Customer Wallet Transaction'

      argument :wallet_id, ID, required: true
      argument :paid_credits, String, required: true
      argument :granted_credits, String, required: true

      type Types::WalletTransactions::Object

      def resolve(**args)
        validate_organization!

        # TODO
      end
    end
  end
end
