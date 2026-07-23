# frozen_string_literal: true

module Mutations
  module PaymentProviderCustomers
    class Destroy < BaseMutation
      include AuthenticableApiUser
      include RequiredOrganization

      REQUIRED_PERMISSION = "customers:update"

      graphql_name "DestroyPaymentProviderCustomer"
      description "Deletes a payment provider customer connection"

      argument :id, ID, required: true

      field :id, ID, null: true

      def resolve(id:)
        payment_provider_customer = ::PaymentProviderCustomers::BaseCustomer
          .where(organization_id: current_organization.id)
          .find_by(id:)

        result = ::PaymentProviderCustomers::DestroyService.call(payment_provider_customer:)

        result.success? ? result.payment_provider_customer : result_error(result)
      end
    end
  end
end
