# frozen_string_literal: true

module Subscriptions
  module Concerns
    # Refreshes the billing periods of a subscription from a lifecycle service.
    #
    # The periods are derived data: their writer takes a lock held until the lifecycle transaction
    # commits, so a refresh running alongside one can fail to acquire it — and a subscription being
    # created, terminated or upgraded must not be rolled back over its bookkeeping.
    #
    # The refresh is then handed to the job, which retries on the lock, and the failure is reported
    # so that a writer losing the race stays visible rather than only showing up in the nightly
    # detection.
    module BillingPeriodsRefreshConcern
      extend ActiveSupport::Concern

      private

      def refresh_billing_periods(subscription)
        Subscriptions::BillingPeriods::UpsertService.call!(subscription:)
      rescue BaseLockService::FailedToAcquireLock => e
        Sentry.capture_exception(e, extra: {subscription_id: subscription.id})

        Subscriptions::BillingPeriods::UpsertJob.perform_after_commit(subscription.id)
      end
    end
  end
end
