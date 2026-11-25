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
      target = migration || mapped_migration
      if target && anything_to_reconcile?(target.shadow_organization_id)
        CopySubscriptionAlertsJob.perform_later(target.id, subscription)
      end
    rescue RedisClient::Error, Redlock::LockError, ActiveRecord::ActiveRecordError => e
      Sentry.capture_exception(e, extra: {subscription_id: subscription.id})
    end

    def mapped_migration
      entry = Lookup.for_source(subscription.organization_id)
      entry if entry&.plan_mapping&.key?(subscription.plan.code)
    end

    # Most subscriptions have no alert: skip the job unless a V1 alert or a copy exists on the external id
    def anything_to_reconcile?(shadow_organization_id)
      subscription.alerts.exists? ||
        UsageMonitoring::ContractAlert.exists?(organization_id: shadow_organization_id, contract_external_id: subscription.external_id)
    end
  end
end
