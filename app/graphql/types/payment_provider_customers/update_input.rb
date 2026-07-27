# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class UpdateInput < BaseInputObject
      graphql_name "UpdatePaymentProviderCustomerInput"
      description "Update payment provider customer input arguments"

      argument :id, ID, required: true

      argument :code, String, required: false
      argument :provider_customer_id, ID, required: false
      argument :provider_payment_methods, [Types::PaymentProviderCustomers::ProviderPaymentMethodsEnum], required: false
      argument :sync_with_provider, Boolean, required: false
    end
  end
end
