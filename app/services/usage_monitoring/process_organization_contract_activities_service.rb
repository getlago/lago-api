# frozen_string_literal: true

module UsageMonitoring
  class ProcessOrganizationContractActivitiesService < BaseService
    Result = BaseResult[:nb_jobs_enqueued]

    BATCH_SIZE = 500

    def initialize(organization:)
      @organization = organization
      super
    end

    def call
      # Dropped rather than kept, so the clock stops picking the organization up while the flag is off
      unless organization.feature_flag_enabled?(:contract_alerts)
        organization.contract_activities.where(enqueued: false).delete_all
        result.nb_jobs_enqueued = 0
        return result
      end

      nb_jobs_enqueued = 0

      queue_name = Utils::DedicatedWorkerConfig.queue_for(
        organization.id,
        dedicated: Utils::DedicatedWorkerConfig::DEDICATED_ALERTS_QUEUE,
        default: ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"]) ? :alerts : :default
      ).to_s

      organization.contract_activities.where(enqueued: false).select(:id).in_batches(of: BATCH_SIZE) do |batch|
        jobs = batch.map do |contract_activity|
          ProcessContractActivityJob.new(contract_activity.id).tap { |job| job.queue_name = queue_name }
        end

        ActiveRecord::Base.transaction do
          batch.update_all(enqueued: true, enqueued_at: Time.current) # rubocop:disable Rails/SkipsModelValidations, Lago/UpdateAllUpdatedAt -- the table has no updated_at
          after_commit { ApplicationJob.perform_all_later(jobs) }
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
