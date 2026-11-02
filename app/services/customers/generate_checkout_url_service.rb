# frozen_string_literal: true

module Customers
  class GenerateCheckoutUrlService < BaseService
    Result = BaseResult

    def initialize(customer:)
      @customer = customer
      @provider_customer = customer&.provider_customer

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") if customer.blank?

      if provider_customer.blank?
        return result.single_validation_failure!(
          error_code: "no_linked_payment_provider"
        )
      end

      PaymentProviderCustomers::Factory.for(provider_customer)
        .call(:generate_checkout_url, provider_customer, send_webhook: false)
    # The provider services raise these for the checkout URL jobs, which retry on them. A request
    # answers them at once.
    rescue ::Adyen::AdyenError => e
      result.third_party_failure!(third_party: "Adyen", error_code: e.code, error_message: e.msg)
    rescue ::GoCardlessPro::Error => e
      result.third_party_failure!(third_party: "GoCardless", error_code: e.code, error_message: e.message)
    rescue ::Stripe::StripeError => e
      result.third_party_failure!(third_party: "Stripe", error_code: e.code, error_message: e.message)
    end

    private

    attr_reader :customer, :provider_customer
  end
end
