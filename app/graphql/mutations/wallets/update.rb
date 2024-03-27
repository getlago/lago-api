# frozen_string_literal: true

module Mutations
  module Wallets
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "UpdateCustomerWallet"
      description "Updates a new Customer Wallet"

      input_object_class Types::Wallets::UpdateInput

      type Types::Wallets::Object

      def resolve(**args)
        wallet = context[:current_user].wallets.find_by(id: args[:id])

        result = ::Wallets::UpdateService
          .new(context[:current_user])
          .update(
            wallet:,
            args:
          )

        result.success? ? result.wallet : result_error(result)
      end
    end
  end
end
