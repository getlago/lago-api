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
        result = ::WalletTransactions::CreateService.new(context[:current_user]).call(
          organization_id: current_organization.id,
          wallet_id: args[:wallet_id],
          paid_credits: args[:paid_credits],
          granted_credits: args[:granted_credits],
        )

        result.success? ? result.wallet_transactions : result_error(result)
      end
    end
  end
end
