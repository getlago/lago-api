# frozen_string_literal: true

module Clock
  class TerminateEndedSubscriptionsJob < ClockJob
    ENDING_AT_PREFILTER = 3.days

    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    def perform
      now = Time.current

      # Optimization: the DATE comparison below reads the timezone from a joined
      # row, so no index can help it and Postgres checks every active subscription
      # one by one. The separate ending_at range is plain UTC, so it is indexed and
      # runs first. It does not change the result: every row the DATE comparison
      # matches fits in it, with room to spare for any timezone.
      Subscription
        .joins(customer: :billing_entity)
        .active
        .where(ending_at: (now - ENDING_AT_PREFILTER)..(now + ENDING_AT_PREFILTER))
        .where(
          "DATE(subscriptions.ending_at#{Utils::Timezone.at_time_zone_sql}) = " \
          "DATE(?#{Utils::Timezone.at_time_zone_sql})",
          now
        )
        .find_each do |subscription|
          Subscriptions::TerminateEndedSubscriptionJob.perform_later(subscription)
        end
    end
  end
end
