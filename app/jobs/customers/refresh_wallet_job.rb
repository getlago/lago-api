# frozen_string_literal: true

module Customers
  class RefreshWalletJob < ApplicationJob
    queue_as "low_priority"

    unique :until_executed, on_conflict: :log, lock_ttl: 12.hours

    retry_on ActiveRecord::StaleObjectError, wait: :polynomially_longer, attempts: 6
    retry_on BaseService::TooManyProviderRequestsFailure, wait: :polynomially_longer, attempts: 25
    retry_on Net::ReadTimeout, Integrations::Aggregator::BadGatewayError, wait: :polynomially_longer, attempts: 6

    def perform(customer)
      return unless customer.awaiting_wallet_refresh?

      result = Customers::RefreshWalletsService.call(customer:)

      # NOTE: We don't want a dead job for tax provider errors (e.g. missing customer address).
      #       The webhook `customer.tax_provider_error` is already sent by the tax provider service.
      return if tax_error?(result)

      result.raise_if_error!
    end

    private

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error.messages&.dig(:tax_error).present?
    end
  end
end
