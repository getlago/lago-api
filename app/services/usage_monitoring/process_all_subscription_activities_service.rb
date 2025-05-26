# frozen_string_literal: true

module UsageMonitoring
  class ProcessAllSubscriptionActivitiesService < BaseService
    Result = BaseResult

    def call
      # NOTE: If we need to handle different delays per organization, this would be done here.
      #     This is also where we should report metrics
      #     That's why it's a dedicated service and not just done in the job

      now = Time.current.iso8601

      SubscriptionActivity.group(:organization_id).count.each do |organization_id, count|
        ProcessOrganizationSubscriptionActivitiesJob.perform_later(organization_id)

        Rails.logger.info({
          metric: "usage_monitoring.subscription_activities_size",
          value: count,
          timestamp: now,
          organization_id: organization_id
        }.to_json)
      end

      result
    end
  end
end
