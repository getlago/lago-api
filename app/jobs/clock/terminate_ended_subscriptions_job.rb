# frozen_string_literal: true

module Clock
  class TerminateEndedSubscriptionsJob < ClockJob
    unique :until_executed, on_conflict: :log, lock_ttl: 4.hours

    def perform
      # NOTE: Terminate every active subscription whose `ending_at` instant has already
      #       passed. This runs hourly (see clock.rb), so a subscription ending at, say,
      #       15:00 is terminated on the next hourly tick after 15:00 — not at midnight.
      #       We compare timestamps (not calendar dates) so we never terminate a
      #       subscription before it actually reaches its `ending_at`.
      Subscription
        .joins(customer: :billing_entity)
        .active
        .where("subscriptions.ending_at <= ?", Time.current)
        .find_each do |subscription|
          Subscriptions::TerminateEndedSubscriptionJob.perform_later(subscription)
        end
    end
  end
end
