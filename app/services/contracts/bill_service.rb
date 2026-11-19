# frozen_string_literal: true

module Contracts
  class BillService < BaseService
    Result = BaseResult[:invoices]

    def initialize(contracts:, end_on:)
      @contracts = contracts
      @end_on = end_on
      super
    end

    def call
      now = Time.current
      result.invoices = []
      contracts.map(&:customer).uniq.each do |customer|
        timestamp = end_on&.in_time_zone(customer.applicable_timezone)&.end_of_day || now
        BillingOperations::ScheduleService.call!(customer:, timestamp:)
        # Each clock pass takes the earliest operation per card. Even a zero-fee pass can advance it.
        loop do
          pass = BillingOperations::ProcessService.call!(customer:, timestamp:)
          result.invoices.concat(pass.invoices)
          break if pass.processed_operations_count.zero?
        end
      end
      result
    rescue BaseLockService::FailedToAcquireLock => error
      result.lock_acquisition_failure!(message: error.message, error:)
    rescue BaseService::FailedResult => error
      result.fail_with_error!(error)
    end

    private

    attr_reader :contracts, :end_on
  end
end
