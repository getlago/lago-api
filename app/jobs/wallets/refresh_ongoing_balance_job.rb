# frozen_string_literal: true

module Wallets
  class RefreshOngoingBalanceJob < ApplicationJob
    queue_as "low_priority"

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6
    retry_on BaseService::TooManyProviderRequestsFailure, wait: :polynomially_longer, attempts: 25
    retry_on Net::ReadTimeout, Integrations::Aggregator::BadGatewayError, wait: :polynomially_longer, attempts: 6

    def perform(wallet)
      return unless wallet.ready_to_be_refreshed?

      Wallets::Balance::RefreshOngoingService.call!(wallet:)
    end
  end
end
