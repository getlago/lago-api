# frozen_string_literal: true

module Mutations
  module CustomerPortal
    module WalletTransactions
      class Create < BaseMutation
        include AuthenticableCustomerPortalUser

        graphql_name "CreateCustomerPortalWalletTransaction"
        description "Creates a new Customer Wallet Transaction from Customer Portal"

        input_object_class Types::CustomerPortal::WalletTransactions::CreateInput

        type Types::CustomerPortal::WalletTransactions::Object.collection_type

        def resolve(**args)
          organization = context[:customer_portal_user].organization
          result = ::WalletTransactions::CreateFromParamsService.call(
            organization:,
            params: args.merge(customer: context[:customer_portal_user])
          )

          result.success? ? result.wallet_transactions : result_error(result)
        end
      end
    end
  end
end
