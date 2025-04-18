# frozen_string_literal: true

module UsageMonitoring
  class ProcessAllSubscriptionActivitiesJob < ApplicationJob
    queue_as :high_priority # yolo

    # TODO: Put this job under Clock:: ?
    def perform
      result = ProcessAllSubscriptionActivitiesService.call!

      Rails.logger.info(
        "ProcessAllSubscriptionActivitiesService enqueued #{result.nb_jobs_enqueued} jobs"
      )
    end
  end
end
