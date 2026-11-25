# frozen_string_literal: true

module BillingEngineMigrations
  class EnqueueSubscriptionAlertsCopyService < BaseService
    Result = BaseResult

    def initialize(subscription:, migration: nil)
      @subscription = subscription
      @migration = migration
      super
    end

    def call
      after_commit { enqueue }
      result
    end

    private

    attr_reader :subscription, :migration

    # Runs after the V1 write committed: a failing lookup reload or an unreachable Redis must not
    # answer an error for a write that succeeded.
    def enqueue
      migration_id = migration&.id || mapped_migration_id
      if migration_id
        CopySubscriptionAlertsJob.perform_later(migration_id, subscription)
      end
    rescue RedisClient::Error, Redlock::LockError, ActiveRecord::ActiveRecordError => e
      Sentry.capture_exception(e, extra: {subscription_id: subscription.id})
    end

    def mapped_migration_id
      entry = Lookup.for_source(subscription.organization_id)
      if entry&.plan_mapping&.key?(subscription.plan.code)
        entry.id
      end
    end
  end
end
