# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackCheckoutUrlJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(paystack_customer)
      PaymentProviderCustomers::PaystackService.call!(:generate_checkout_url, paystack_customer)
    end
  end
end
