# frozen_string_literal: true

module Customers
  class RefreshWalletService < BaseService
    Result = BaseResult

    # @param force [Boolean] refresh even when `awaiting_wallet_refresh` is not set, for an
    #   explicitly requested refresh (e.g. a balance increase) or a fresh ingestion trigger
    # @param lock_timeout_seconds [Integer] how long to wait for the customer's refresh lock
    def initialize(customer:, force: false, lock_timeout_seconds: BaseLockService::ACQUIRE_LOCK_TIMEOUT)
      @customer = customer
      @force = force
      @lock_timeout_seconds = lock_timeout_seconds

      super
    end

    def call
      return result if !force && !customer.awaiting_wallet_refresh?
      return result if customer.error_details.tax_error.exists?

      # Not transactional: the refresh reads ClickHouse and calls the tax provider, too long to
      # hold a transaction open for.
      Customers::LockService.call!(
        customer:,
        scope: :wallet_refresh,
        transaction: false,
        timeout_seconds: lock_timeout_seconds
      ) do
        Customers::RefreshWalletsService.call!(customer:)
      end

      result
    rescue BaseService::ValidationFailure => e
      record_tax_error(e)

      result
    end

    private

    attr_reader :customer, :force, :lock_timeout_seconds

    def record_tax_error(error)
      messages = Array(error.messages[:tax_error])

      raise error unless messages.any? { it.include?(Integrations::Aggregator::Taxes::BaseService::CUSTOMER_ADDRESS_INVALID) }

      ErrorDetails::CreateService.call!(
        owner: customer,
        organization: customer.organization,
        params: {
          error_code: :tax_error,
          details: {
            tax_error: messages.first,
            backtrace: error.backtrace,
            error: error.inspect.to_json
          }.compact
        }
      )
    end
  end
end
