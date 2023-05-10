# frozen_string_literal: true

module PaymentProviderCustomers
  class AdyenCreateJob < ApplicationJob
    queue_as :providers

    retry_on Adyen::AdyenError, wait: :exponentially_longer, attempts: 6

    def perform(adyen_customer)
      result = PaymentProviderCustomers::AdyenService.new(adyen_customer).create
      result.raise_if_error!
    end
  end
end
