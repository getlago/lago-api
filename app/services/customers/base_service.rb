# frozen_string_literal: true

module Customers
  class BaseService < BaseService
    def payment_provider(customer)
      payment_provider_result = PaymentProviders::FindService.new(
        organization_id: customer.organization_id,
        code: customer.payment_provider_code,
      ).call

      return nil if payment_provider_result.error&.code == 'payment_provider_not_found'

      payment_provider_result.raise_if_error!
      payment_provider_result.payment_provider
    end
  end
end
