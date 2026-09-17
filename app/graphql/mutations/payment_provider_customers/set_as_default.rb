# frozen_string_literal: true

module Mutations
  module PaymentProviderCustomers
    class SetAsDefault < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      graphql_name "SetPaymentProviderCustomerAsDefault"
      description "Set a payment connection as the default for the customer"

      REQUIRED_PERMISSION = "customers:update"

      argument :id, ID, required: true

      type Types::PaymentProviderCustomers::Provider

      def resolve(id:)
        payment_provider_customer = ::PaymentProviderCustomers::BaseCustomer
          .where(organization_id: current_organization.id)
          .find_by(id:)

        result = ::PaymentProviderCustomers::SetAsDefaultService.call(payment_provider_customer:)

        result.success? ? result.payment_provider_customer : result_error(result)
      end
    end
  end
end
