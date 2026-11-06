# frozen_string_literal: true

module PaymentProviderCustomers
  class UpdateService < BaseService
    Result = BaseResult

    attr_reader :customer

    def initialize(customer)
      @customer = customer

      super(nil)
    end

    def call
      provider_customer = customer.provider_customer

      # A customer without a default payment provider has no account to push its details to.
      if provider_customer.nil?
        result
      else
        PaymentProviderCustomers::Factory.for(provider_customer).call!(:update, provider_customer)
      end
    end
  end
end
