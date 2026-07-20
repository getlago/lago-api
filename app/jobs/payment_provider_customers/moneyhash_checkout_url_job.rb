# frozen_string_literal: true

module PaymentProviderCustomers
  class MoneyhashCheckoutUrlJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(moneyhash_customer)
      PaymentProviderCustomers::MoneyhashService.call!(:generate_checkout_url, moneyhash_customer)
    end
  end
end
