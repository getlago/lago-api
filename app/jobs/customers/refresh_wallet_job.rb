# frozen_string_literal: true

module Customers
  class RefreshWalletJob < ApplicationJob
    queue_as "low_priority"

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6
    retry_on BaseService::TooManyProviderRequestsFailure, wait: :polynomially_longer, attempts: 25

    retry_on Net::ReadTimeout,
      Integrations::Aggregator::BadGatewayError,
      Integrations::Aggregator::InternalClientError,
      wait: :polynomially_longer, attempts: 10

    def perform(customer)
      return unless customer.awaiting_wallet_refresh?

      Customers::RefreshWalletsService.call!(customer:)
    end
  end
end
