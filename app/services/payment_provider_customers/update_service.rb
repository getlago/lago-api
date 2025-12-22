# frozen_string_literal: true

module PaymentProviderCustomers
  class UpdateService < BaseService
    attr_reader :customer

    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def call
      result = ::PaymentProviders::Registry.new_instance(
        customer.provider_customer&.payment_provider&.payment_type,
        :manage_customer,
        customer.provider_customer
      ).update

      result.raise_if_error!
      result
    end
  end
end
