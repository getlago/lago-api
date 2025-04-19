# frozen_string_literal: true

module UsageMonitoring
  class ProcessAllSubscriptionActivitiesService < BaseService
    Result = BaseResult[:nb_jobs_enqueued]
    def call
      nb_jobs_enqueued = 0

      SubscriptionActivity.select(:id).in_batches(of: 500) do |batch|
        jobs = []
        batch.each do |subscription_activity|
          jobs << ProcessSubscriptionActivityJob.new(subscription_activity.id)
        end
        ActiveJob.perform_all_later(jobs)
        nb_jobs_enqueued += jobs.size
      end

      result.nb_jobs_enqueued = nb_jobs_enqueued
      result
    end
  end
end
