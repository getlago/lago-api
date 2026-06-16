# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackCreateJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(paystack_customer)
      result = PaymentProviderCustomers::PaystackService.new(paystack_customer).create
      result.raise_if_error!
    end
  end
end
