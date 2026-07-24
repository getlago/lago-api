# frozen_string_literal: true

module Mutations
  module PaymentProviderCustomers
    class Update < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:update"

      graphql_name "UpdatePaymentProviderCustomer"
      description "Updates a payment provider customer connection"

      input_object_class Types::PaymentProviderCustomers::UpdateInput

      type Types::PaymentProviderCustomers::Provider

      def resolve(id:, **args)
        payment_provider_customer = ::PaymentProviderCustomers::BaseCustomer
          .where(organization_id: current_organization.id)
          .find_by(id:)

        result = ::PaymentProviderCustomers::UpdateConnectionService.call(
          payment_provider_customer:,
          params: args
        )

        result.success? ? result.payment_provider_customer : result_error(result)
      end
    end
  end
end
