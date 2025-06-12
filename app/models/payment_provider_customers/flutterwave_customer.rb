# frozen_string_literal: true

module PaymentProviderCustomers
  class FlutterwaveCustomer < BaseCustomer
    def require_provider_payment_id?
      false
    end
  end
end
