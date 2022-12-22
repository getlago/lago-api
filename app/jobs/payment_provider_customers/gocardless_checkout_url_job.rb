# frozen_string_literal: true

module PaymentProviderCustomers
  class GocardlessCheckoutUrlJob < ApplicationJob
    queue_as :providers

    retry_on GoCardlessPro::GoCardlessError, wait: :exponentially_longer, attempts: 6
    retry_on GoCardlessPro::ApiError, wait: :exponentially_longer, attempts: 6
    retry_on GoCardlessPro::RateLimitError, wait: :exponentially_longer, attempts: 6

    def perform(gocardless_customer)
      result = PaymentProviderCustomers::GocardlessService.new(gocardless_customer).generate_checkout_url
      result.raise_if_error!
    end
  end
end
