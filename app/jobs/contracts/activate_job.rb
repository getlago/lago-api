# frozen_string_literal: true

module Contracts
  class ActivateJob < ApplicationJob
    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_BILLING"])
        :billing
      else
        :default
      end
    end

    unique :until_executing, on_conflict: :log

    retry_on BaseLockService::FailedToAcquireLock, BaseService::LockAcquisitionFailure,
      attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(contract)
      Contracts::ActivateService.call!(contract:)
    end
  end
end
