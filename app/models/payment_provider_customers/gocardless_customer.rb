# frozen_string_literal: true

module PaymentProviderCustomers
  class GocardlessCustomer < BaseCustomer
    def service
      PaymentProviderCustomers::GocardlessService.new(self)
    end
  end
end
