# frozen_string_literal: true

module Clock
  class TerminateEndedSubscriptionsJob < ClockJob
    retry_on Customers::FailedToAcquireLock, ActiveRecord::StaleObjectError, attempts: MAX_LOCK_RETRY_ATTEMPTS, wait: random_lock_retry_delay

    def perform
      Subscription
        .joins(customer: :billing_entity)
        .active
        .where(
          "DATE(subscriptions.ending_at#{Utils::Timezone.at_time_zone_sql}) = " \
          "DATE(?#{Utils::Timezone.at_time_zone_sql})",
          Time.current
        )
        .find_each do |subscription|
          Subscriptions::TerminateService.call(subscription:)
        end
    end
  end
end
