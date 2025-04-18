# frozen_string_literal: true

module UsageMonitoring
  class ProcessAllSubscriptionActivitiesService < BaseService
    Result = BaseResult[:nb_jobs_enqueued]
    def call
      jobs = []
      nb_jobs_enqueued = 0

      SubscriptionActivity.select(:id).find_each do |subscription_activity|
        jobs << ProcessSubscriptionActivityJob.new(subscription_activity.id)

        if jobs.size >= 500
          ActiveJob.perform_all_later(jobs)
          nb_jobs_enqueued += jobs.size
          jobs = []
        end
      end

      ActiveJob.perform_all_later(jobs)
      nb_jobs_enqueued += jobs.size

      result.nb_jobs_enqueued = nb_jobs_enqueued
      result
    end
  end
end
