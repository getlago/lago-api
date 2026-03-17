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
      return if customer.error_details.tax_error.exists?

      Customers::RefreshWalletsService.call!(customer:)
    rescue BaseService::ValidationFailure => e
      raise unless Array(e.messages[:tax_error]).any? { |msg| msg.include?(Integrations::Aggregator::Taxes::BaseService::CUSTOMER_ADDRESS_INVALID) }

      ErrorDetails::CreateService.call!(
        owner: customer,
        organization: customer.organization,
        params: {
          error_code: :tax_error,
          details: {
            tax_error: e.messages[:tax_error]&.first,
            backtrace: e.backtrace,
            error: e.inspect.to_json
          }.compact
        }
      )
    end
  end
end
