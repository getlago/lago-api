# frozen_string_literal: true

module Types
  module PaymentProviderCustomers
    class CreateInput < BaseInputObject
      graphql_name "CreatePaymentProviderCustomerInput"
      description "Create payment provider customer input arguments"

      argument :customer_id, ID, required: true
      argument :payment_provider, Types::PaymentProviders::ProviderTypeEnum, required: true

      argument :code, String, required: false
      argument :payment_provider_code, String, required: false
      argument :provider_customer_id, ID, required: false
      argument :provider_payment_methods, [Types::PaymentProviderCustomers::ProviderPaymentMethodsEnum], required: false
      argument :sync_with_provider, Boolean, required: false
    end
  end
end
