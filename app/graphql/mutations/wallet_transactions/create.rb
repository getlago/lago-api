# frozen_string_literal: true

module Mutations
  module WalletTransactions
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = 'wallets:top_up'

      graphql_name 'CreateCustomerWalletTransaction'
      description 'Creates a new Customer Wallet Transaction'

      argument :wallet_id, ID, required: true

      argument :granted_credits, String, required: false
      argument :paid_credits, String, required: false
      argument :voided_credits, String, required: false

      type Types::WalletTransactions::Object.collection_type

      def resolve(**args)
        result = ::WalletTransactions::CreateService.call(organization: current_organization, params: args)

        result.success? ? result.wallet_transactions : result_error(result)
      end
    end
  end
end
