# frozen_string_literal: true

module Orders
  class ExecuteOrderJob < ApplicationJob
    queue_as :default

    unique :until_executed, on_conflict: :log

    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(order)
      Orders::ExecuteService.call!(order:)
    end
  end
end
