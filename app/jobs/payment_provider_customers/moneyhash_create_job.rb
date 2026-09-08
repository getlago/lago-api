# frozen_string_literal: true

module PaymentProviderCustomers
  class MoneyhashCreateJob < ApplicationJob
    queue_as :providers

    retry_on ActiveJob::DeserializationError

    def perform(moneyhash_customer)
      PaymentProviderCustomers::MoneyhashService.call!(:create, moneyhash_customer)
    end
  end
end
