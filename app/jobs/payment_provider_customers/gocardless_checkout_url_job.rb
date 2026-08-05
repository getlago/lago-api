# frozen_string_literal: true

module PaymentProviderCustomers
  class GocardlessCheckoutUrlJob < ApplicationJob
    queue_as :providers

    retry_on GoCardlessPro::GoCardlessError, wait: :polynomially_longer, attempts: 6
    retry_on GoCardlessPro::ApiError, wait: :polynomially_longer, attempts: 6
    retry_on GoCardlessPro::RateLimitError, wait: :polynomially_longer, attempts: 6
    retry_on ActiveJob::DeserializationError

    def perform(gocardless_customer)
      PaymentProviderCustomers::GocardlessService.call!(:generate_checkout_url, gocardless_customer)
    end
  end
end
