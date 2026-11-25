# frozen_string_literal: true

module Customers
  class TerminateRelationsJob < ApplicationJob
    retry_on BaseService::LockAcquisitionFailure, BaseLockService::FailedToAcquireLock,
      attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(customer_id:)
      customer = Customer.with_discarded.find_by(id: customer_id)

      result = Customers::TerminateRelationsService.call(customer:)
      result.raise_if_error!
    end
  end
end
