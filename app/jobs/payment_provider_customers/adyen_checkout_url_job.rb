# frozen_string_literal: true

module PaymentProviderCustomers
  class AdyenCheckoutUrlJob < ApplicationJob
    queue_as :providers

    retry_on Adyen::AdyenError, wait: :polynomially_longer, attempts: 6
    retry_on ActiveJob::DeserializationError

    def perform(adyen_customer)
      PaymentProviderCustomers::AdyenService.call!(:generate_checkout_url, adyen_customer)
    end
  end
end
