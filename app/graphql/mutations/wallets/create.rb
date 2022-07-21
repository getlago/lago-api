# frozen_string_literal: true

module Mutations
  module Wallets
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name 'CreateCustomerWallet'
      description 'Creates a new Customer Wallet'

      argument :customer_id, String, required: true
      argument :rate_amount, String, required: true
      argument :name, String, required: false
      argument :paid_credits, String, required: true
      argument :granted_credits, String, required: true
      argument :expiration_date, GraphQL::Types::ISO8601Date, required: false

      type Types::Wallets::Object

      def resolve(**args)
        # Empty
      end
    end
  end
end
