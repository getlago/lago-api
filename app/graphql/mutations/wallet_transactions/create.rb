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

      type Types::WalletTransactions::Object.collection_type

      def resolve(**args)
        validate_organization!

        result = ::WalletTransactions::CreateService.new.create(
          organization_id: current_organization.id,
          customer_id: customer(args[:wallet_id])&.customer_id,
          wallet_id: args[:wallet_id],
          paid_credits: args[:paid_credits],
          granted_credits: args[:granted_credits],
        )

        result.success? ? result.wallet_transactions : result_error(result)
      end

      private

      def customer(wallet_id)
        Wallet.find_by(id: wallet_id)&.customer
      end
    end
  end
end
