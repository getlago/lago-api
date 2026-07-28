# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackCustomer < BaseCustomer
    PAYMENT_METHODS = %w[card].freeze

    settings_accessors :authorization_code, :payment_method_id
  end
end
