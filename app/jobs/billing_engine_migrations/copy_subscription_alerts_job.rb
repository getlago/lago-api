# frozen_string_literal: true

module BillingEngineMigrations
  class CopySubscriptionAlertsJob < ApplicationJob
    queue_as :low_priority

    unique :until_executing, on_conflict: :log

    retry_on BaseLockService::FailedToAcquireLock, BaseService::LockAcquisitionFailure,
      attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(migration_id, subscription)
      migration = BillingEngineMigration.find_by(id: migration_id)
      BillingEngineMigrations::CopySubscriptionAlertsService.call!(migration:, subscription:) if migration
    end
  end
end
