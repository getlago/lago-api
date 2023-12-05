# frozen_string_literal: true

module PaymentProviderCustomers
  class UpdateService < BaseService
    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def call
      result = "PaymentProviderCustomers::#{provider_name}Service".constantize.new(customer.provider_customer).update
      result.raise_if_error!
      result
    end

    private

    attr_accessor :customer

    def provider_name
      /\APaymentProviderCustomers::(.+)Customer\z/.match(customer.provider_customer.type)[1]
    end
  end
end
