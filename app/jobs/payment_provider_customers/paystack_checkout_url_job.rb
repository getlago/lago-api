# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackCheckoutUrlJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(paystack_customer)
      result = PaymentProviderCustomers::PaystackService.new(paystack_customer).generate_checkout_url
      result.raise_if_error!
    end
  end
end
