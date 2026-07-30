# frozen_string_literal: true

module PaymentProviderCustomers
  class DestroyService < BaseService
    Result = BaseResult[:payment_provider_customer]

    def initialize(payment_provider_customer:)
      @payment_provider_customer = payment_provider_customer

      super
    end

    def call
      return result.not_found_failure!(resource: "payment_provider_customer") unless payment_provider_customer

      ActiveRecord::Base.transaction do
        payment_provider_customer.is_default = false
        payment_provider_customer.discard!

        payment_provider_customer.payment_methods.find_each do |payment_method|
          PaymentMethods::DestroyService.call!(payment_method:)
        end
      end

      result.payment_provider_customer = payment_provider_customer
      result
    end

    private

    attr_reader :payment_provider_customer
  end
end
