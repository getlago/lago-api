# frozen_string_literal: true

module UsageMonitoring
  class ProcessOrganizationSubscriptionActivitiesService < BaseService
    Result = BaseResult[:nb_jobs_enqueued]

    BATCH_SIZE = 500

    def initialize(organization:)
      @organization = organization
      super()
    end

    def call
      nb_jobs_enqueued = 0

      # NOTE: If we need to handle different delays per organization, this would be done here.

      organization.subscription_activities.where(enqueued: false).select(:id).in_batches(of: BATCH_SIZE) do |batch|
        jobs = []
        batch.each do |subscription_activity|
          jobs << ProcessSubscriptionActivityJob.new(subscription_activity.id)
        end

        ActiveRecord::Base.transaction do
          batch.update_all(enqueued: true, enqueued_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
          after_commit { ActiveJob.perform_all_later(jobs) }
        end

        nb_jobs_enqueued += jobs.size
      end

      result.nb_jobs_enqueued = nb_jobs_enqueued
      result
    end

    private

    attr_reader :organization
  end
end
