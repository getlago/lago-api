# frozen_string_literal: true

module PaymentProviderCustomers
  class SetAsDefaultService < ::BaseService
    Result = BaseResult[:payment_provider_customer]

    def initialize(payment_provider_customer:)
      @payment_provider_customer = payment_provider_customer

      super
    end

    def call
      return result.not_found_failure!(resource: "payment_provider_customer") unless payment_provider_customer

      if payment_provider_customer.is_default?
        result.payment_provider_customer = payment_provider_customer
        return result
      end

      ActiveRecord::Base.transaction do
        Customers::LockService.call(customer: payment_provider_customer.customer, scope: :payment_provider_customer) do
          payment_provider_customer.customer.payment_provider_customers
            .where.not(id: payment_provider_customer.id)
            .update!(is_default: false)
          payment_provider_customer.update!(is_default: true)
        end
      end

      result.payment_provider_customer = payment_provider_customer

      result
    rescue BaseLockService::FailedToAcquireLock => e
      result.lock_acquisition_failure!(message: e.message, error: e)
    end

    private

    attr_reader :payment_provider_customer
  end
end
