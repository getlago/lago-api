# frozen_string_literal: true

module Customers
  class RefreshWalletJob < ApplicationJob
    queue_as "low_priority"

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6
    retry_on BaseService::TooManyProviderRequestsFailure, wait: :polynomially_longer, attempts: 25
    retry_on Net::ReadTimeout, Integrations::Aggregator::BadGatewayError, wait: :polynomially_longer, attempts: 6

    def perform(customer)
      return unless customer.wallets.active.exists?(ready_to_be_refreshed: true)

      Customers::RefreshWalletsService.call!(customer:)
    end
  end
end
