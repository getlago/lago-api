# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackCustomer < BaseCustomer
    settings_accessors :authorization_code, :payment_method_id

    def provider_payment_methods
      ["card"]
    end
  end
end
