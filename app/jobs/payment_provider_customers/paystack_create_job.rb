# frozen_string_literal: true

module PaymentProviderCustomers
  class PaystackCreateJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(paystack_customer)
      PaymentProviderCustomers::PaystackService.call!(:create, paystack_customer)
    end
  end
end
