# frozen_string_literal: true

module PaymentProviderCustomers
  class PinetCustomer < BaseCustomer
    def payment_token
      get_from_settings('payment_token')
    end

    def payment_token=(payment_token)
      push_to_settings(key: 'payment_token', value: payment_token)
    end
  end
end
