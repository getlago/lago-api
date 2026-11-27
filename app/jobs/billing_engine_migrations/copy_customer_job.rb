# frozen_string_literal: true

module BillingEngineMigrations
  class CopyCustomerJob < ApplicationJob
    queue_as :low_priority

    unique :until_executing, on_conflict: :log

    retry_on BaseLockService::FailedToAcquireLock, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(migration_id, customer_id)
      migration = BillingEngineMigration.find(migration_id)
      customer = Customer.find_by(id: customer_id, organization_id: migration.organization_id)
      BillingEngineMigrations::CopyCustomerService.call!(migration:, customer:) if customer
    end
  end
end
