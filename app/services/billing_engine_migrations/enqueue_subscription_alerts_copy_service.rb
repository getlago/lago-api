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
      target = migration ? (migration if anything_to_reconcile?) : mapped_migration
      CopySubscriptionAlertsJob.perform_later(target.id, subscription) if target
    rescue RedisClient::Error, Redlock::LockError, ActiveRecord::ActiveRecordError => e
      Sentry.capture_exception(e, extra: {subscription_id: subscription.id})
    end

    def mapped_migration
      entry = Lookup.for_source(subscription.organization_id)
      entry if entry&.plan_mapping&.key?(subscription.plan.code)
    end

    # Most new contracts have no alert to copy. An alert write is never skipped: after a `destroy_all`
    # there is no alert left, yet a job already running may still create copies of them.
    def anything_to_reconcile?
      subscription.alerts.exists? ||
        UsageMonitoring::ContractAlert.exists?(organization_id: migration.shadow_organization_id, contract_external_id: subscription.external_id)
    end
  end
end
