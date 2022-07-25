# frozen_string_literal: true

module Mutations
  module Wallets
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'UpdateCustomerWallet'
      description 'Updates a new Customer Wallet'

      argument :id, ID, required: true
      argument :name, String, required: false
      argument :expiration_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Wallets::Object

      def resolve(**args)
        result = ::Wallets::UpdateService
          .new(context[:current_user])
          .update(**args)

        result.success? ? result.wallet : result_error(result)
      end
    end
  end
end
