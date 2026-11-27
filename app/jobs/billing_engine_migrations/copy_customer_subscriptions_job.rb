# frozen_string_literal: true

module BillingEngineMigrations
  class CopyCustomerSubscriptionsJob < ApplicationJob
    queue_as :low_priority

    unique :until_executing, on_conflict: :log

    retry_on BaseLockService::FailedToAcquireLock, BaseService::LockAcquisitionFailure,
      attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform(migration, subscription_ids)
      subscriptions(migration, subscription_ids).each do |subscription|
        BillingEngineMigrations::CopySubscriptionService.call!(migration:, subscription:)
      end
    end

    private

    def subscriptions(migration, subscription_ids)
      migration.organization.subscriptions
        .where(id: subscription_ids)
        .preload(:plan, :customer)
        .order(:started_at, :id)
    end
  end
end
