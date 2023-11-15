# frozen_string_literal: true

module Customers
  class GenerateCheckoutUrlService < BaseService
    def initialize(customer:)
      @customer = customer
      @provider_customer = customer&.provider_customer

      super
    end

    def call
      return result.not_found_failure!(resource: 'customer') if customer.blank?

      if provider_customer.blank?
        return result.service_failure!(
          code: 400,
          message: 'no payment provider linked to this customer',
        )
      end

      provider_customer.service.generate_checkout_url(send_webhook: false)
    end

    private

    attr_reader :customer, :provider_customer
  end
end
