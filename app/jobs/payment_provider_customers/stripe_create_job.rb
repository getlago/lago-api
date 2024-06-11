# frozen_string_literal: true

module PaymentProviderCustomers
  class StripeCreateJob < ApplicationJob
    queue_as :providers

    retry_on Stripe::APIConnectionError, wait: :exponentially_longer, attempts: 6
    retry_on Stripe::APIError, wait: :exponentially_longer, attempts: 6
    retry_on Stripe::RateLimitError, wait: :exponentially_longer, attempts: 6
    retry_on ActiveJob::DeserializationError

    def perform(stripe_customer)
      result = PaymentProviderCustomers::StripeService.new(stripe_customer).create
      result.raise_if_error!
    rescue BaseService::UnauthorizedFailure => e
      Rails.logger.warn(e.message)
    end
  end
end
