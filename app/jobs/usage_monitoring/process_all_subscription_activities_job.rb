# frozen_string_literal: true

module UsageMonitoring
  class ProcessAllSubscriptionActivitiesJob < ApplicationJob
    queue_as :high_priority # yolo

    def perform
      jobs = []

      SubscriptionActivity.find_each do |subscription_activity|
        jobs << ProcessSubscriptionActivityJob.new(subscription_activity.id)

        if jobs.size >= 500
          ActiveJob.perform_all_later(jobs)
          jobs = []
        end
      end

      ActiveJob.perform_all_later(jobs)
    end
  end
end
