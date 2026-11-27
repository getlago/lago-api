# frozen_string_literal: true

module PaymentProviderCustomers
  class SetDefaultIfUnsetService < ::BaseService
    Result = BaseResult[:payment_provider_customer]

    def initialize(customer:)
      @customer = customer

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") unless customer

      connection = customer.provider_customer
      return result unless connection
      return result if another_connection_is_default?(connection)

      PaymentProviderCustomers::SetAsDefaultService.call!(payment_provider_customer: connection)

      result.payment_provider_customer = connection
      result
    end

    private

    attr_reader :customer

    def another_connection_is_default?(connection)
      customer.payment_provider_customers.where.not(id: connection.id).exists?(is_default: true)
    end
  end
end
