# frozen_string_literal: true

module Mutations
  module Wallets
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "CreateCustomerWallet"
      description "Creates a new Customer Wallet"

      input_object_class Types::Wallets::CreateInput

      type Types::Wallets::Object

      def resolve(**args)
        validate_organization!

        result = ::Wallets::CreateService
          .new(context[:current_user])
          .create(
            args
              .merge(organization_id: current_organization.id)
              .merge(customer: current_customer(args[:customer_id]))
              .except(:customer_id)
          )

        result.success? ? result.wallet : result_error(result)
      end

      def current_customer(id)
        Customer.find_by(id:, organization_id: current_organization.id)
      end
    end
  end
end
