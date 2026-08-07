# frozen_string_literal: true

module Clock
  class RefreshSubscriptionBillingPeriodsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Subscription.active.includes(:plan).find_each do |subscription|
        Subscriptions::BillingPeriods::UpsertService.call(subscription:)
      rescue => e
        Sentry.capture_exception(e)
      end
    end
  end
end
