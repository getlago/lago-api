# frozen_string_literal: true

module Clock
  class TerminateEndedSubscriptionsJob < ApplicationJob
    queue_as 'clock'

    def perform
      Subscription
        .joins(customer: :organization)
        .active
        .where("DATE(subscriptions.ending_at#{Utils::TimezoneService.at_time_zone}) = "\
               "DATE(?#{Utils::TimezoneService.at_time_zone})", Time.current)
        .find_each do |subscription|
          Subscriptions::TerminateService.call(subscription:)
        end
    end
  end
end
