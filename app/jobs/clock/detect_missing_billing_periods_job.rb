# frozen_string_literal: true

module Clock
  # Safety net for the periods maintained by the subscription lifecycle services: heals any active
  # subscription left without a covering period, and reports how many there were.
  #
  # A non-zero count is a bug, not routine — it means a path that moves a subscription's billing
  # dates is not maintaining its periods. Watch it.
  class DetectMissingBillingPeriodsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 30.minutes

    def perform
      Organization.find_each { |organization| heal(organization) }
    end

    private

    def heal(organization)
      missing = organization.subscriptions.active.where.not(
        SubscriptionBillingPeriod
          .covering(Time.current)
          .where("subscription_billing_periods.subscription_id = subscriptions.id")
          .arel.exists
      )

      count = 0
      missing.find_each do |subscription|
        Subscriptions::BillingPeriods::UpsertJob.perform_later(subscription.id)
        count += 1
      end
      return if count.zero?

      Rails.logger.warn(
        "[billing_periods] #{count} active subscriptions without a covering period " \
        "organization_id=#{organization.id}"
      )
    end
  end
end
