# frozen_string_literal: true

module Clock
  class RefreshSubscriptionUsagesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      return unless License.premium?

      Subscription.joins(usage_activity: :organization)
        .merge(Organization.with_progressive_billing_support.or(Organization.with_lifetime_usage_support).or(Organization.with_alerting_total_usage_support))
        .where(usage_activity: {recalculate_current_usage: true})
        .find_each { Subscriptions::RecalculateUsageJob.perform_later(_1) }
    end
  end
end
