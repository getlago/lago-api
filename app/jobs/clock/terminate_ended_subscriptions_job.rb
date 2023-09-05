# frozen_string_literal: true

module Clock
  class TerminateEndedSubscriptionsJob < ApplicationJob
    queue_as 'clock'

    def perform
      Subscription
        .joins(customer: :organization)
        .active
        .where("DATE(#{Subscription.ending_at_in_timezone_sql}) = ?", Time.current.to_date)
        .find_each do |subscription|
          Subscriptions::TerminateService.call(subscription:)
        end
    end
  end
end
