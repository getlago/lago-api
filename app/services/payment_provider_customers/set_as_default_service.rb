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
        payment_provider_customer.customer.payment_provider_customers
          .where.not(id: payment_provider_customer.id)
          .update_all(is_default: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
        payment_provider_customer.update!(is_default: true)
      end

      result.payment_provider_customer = payment_provider_customer

      result
    end

    private

    attr_reader :payment_provider_customer
  end
end
