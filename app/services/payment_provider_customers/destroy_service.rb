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

        clear_customer_payment_provider
      end

      result.payment_provider_customer = payment_provider_customer
      result
    end

    private

    attr_reader :payment_provider_customer

    # Keep the customer in the same end state as removing the provider through
    # Customers::UpdateService: when the destroyed connection is the customer's active provider,
    # clear the pointers so nothing references a connection that no longer exists.
    def clear_customer_payment_provider
      customer = payment_provider_customer.customer
      return unless customer.payment_provider == provider_type

      customer.update!(payment_provider: nil, payment_provider_code: nil)
    end

    def provider_type
      payment_provider_customer.type.demodulize.underscore.delete_suffix("_customer")
    end
  end
end
