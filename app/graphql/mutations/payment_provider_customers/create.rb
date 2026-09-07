# frozen_string_literal: true

module Mutations
  module PaymentProviderCustomers
    class Create < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:update"

      graphql_name "CreatePaymentProviderCustomer"
      description "Creates a payment provider customer connection"

      input_object_class Types::PaymentProviderCustomers::CreateInput

      type Types::PaymentProviderCustomers::Provider

      def resolve(customer_id:, **args)
        customer = current_organization.customers.find_by(id: customer_id)

        result = ::PaymentProviderCustomers::CreateConnectionService.call(customer:, params: args)

        result.success? ? result.payment_provider_customer : result_error(result)
      end
    end
  end
end
