# frozen_string_literal: true

module PaymentProviderCustomers
  class AdyenCustomer < BaseCustomer
    settings_accessors :payment_method_id
  end
end
