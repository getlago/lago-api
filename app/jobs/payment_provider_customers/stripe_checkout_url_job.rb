# frozen_string_literal: true

module PaymentProviderCustomers
  class StripeCheckoutUrlJob < ApplicationJob
    queue_as :providers

    retry_on Stripe::APIConnectionError, wait: :polynomially_longer, attempts: 6
    retry_on Stripe::APIError, wait: :polynomially_longer, attempts: 6
    retry_on Stripe::RateLimitError, wait: :polynomially_longer, attempts: 6
    retry_on ActiveJob::DeserializationError

    def perform(stripe_customer)
      result = PaymentProviderCustomers::StripeService.new(stripe_customer).generate_checkout_url
      result.raise_if_error!
    end
  end
end
