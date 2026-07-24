# frozen_string_literal: true

module Mutations
  module PaymentProviderCustomers
    class SetAsDefault < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "SetPaymentProviderCustomerAsDefault"
      description "Set a payment connection as the default for the customer"

      REQUIRED_PERMISSION = "customers:update"

      argument :code, String, required: true
      argument :customer_id, ID, required: true

      type Types::PaymentProviderCustomers::Provider

      def resolve(**args)
        customer = current_organization.customers.find_by(id: args[:customer_id])
        payment_provider_customer = customer&.payment_provider_customers&.find_by(code: args[:code])

        result = ::PaymentProviderCustomers::SetAsDefaultService.call(payment_provider_customer:)

        result.success? ? result.payment_provider_customer : result_error(result)
      end
    end
  end
end
