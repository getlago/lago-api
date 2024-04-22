# frozen_string_literal: true

module Mutations
  module WalletTransactions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCustomerWalletTransaction'
      description 'Creates a new Customer Wallet Transaction'

      argument :granted_credits, String, required: true
      argument :paid_credits, String, required: true
      argument :wallet_id, ID, required: true

      type Types::WalletTransactions::Object.collection_type

      def resolve(**args)
        result = ::WalletTransactions::CreateService.call(organization: current_organization, params: args)

        result.success? ? result.wallet_transactions : result_error(result)
      end
    end
  end
end
