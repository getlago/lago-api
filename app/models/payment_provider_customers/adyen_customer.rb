# frozen_string_literal: true

module PaymentProviderCustomers
  class AdyenCustomer < BaseCustomer
    def payment_method_id
      get_from_settings('payment_method_id')
    end

    def payment_method_id=(payment_method_id)
      push_to_settings(key: 'payment_method_id', value: payment_method_id)
    end

    def service
      PaymentProviderCustomers::AdyenService.new(self)
    end
  end
end
