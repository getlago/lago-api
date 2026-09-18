# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackCustomer < BaseCustomer
    PAYMENT_METHODS = %w[card].freeze

    settings_accessors :authorization_code, :payment_method_id

    def provider_payment_methods
      PAYMENT_METHODS
    end
  end
end
