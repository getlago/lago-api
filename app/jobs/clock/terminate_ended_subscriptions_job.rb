# frozen_string_literal: true

module Clock
  class TerminateEndedSubscriptionsJob < ClockJob
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
          Subscriptions::TerminateEndedSubscriptionJob.perform_later(subscription)
        end
    end
  end
end
