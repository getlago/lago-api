# frozen_string_literal: true

module Mutations
  module Wallets
    class Terminate < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'TerminateCustomerWallet'
      description 'Terminates a new Customer Wallet'

      argument :id, ID, required: true

      type Types::Wallets::Object

      def resolve(**args)
        result = ::Wallets::TerminateService.new(context[:current_user]).terminate(id)

        result.success? ? result.coupon : result_error(result)
      end
    end
  end
end
