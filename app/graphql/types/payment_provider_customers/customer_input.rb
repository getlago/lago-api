# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class CustomerInput < Types::BaseInputObject
      graphql_name "PaymentProviderCustomerInput"

      argument :id, ID, required: false

      # NOTE: code "lago_manual" flags the reserved null-provider connection; provider connections
      # carry their own code and payment provider.
      argument :code, String, required: false

      argument :payment_provider, Types::PaymentProviders::ProviderTypeEnum, required: false
      argument :payment_provider_code, String, required: false
      argument :provider_customer_id, ID, required: false
      argument :provider_payment_methods, [Types::PaymentProviderCustomers::ProviderPaymentMethodsEnum], required: false
      argument :sync_with_provider, Boolean, required: false
    end
  end
end
