# frozen_string_literal: true

module UsageMonitoring
  class ProcessAllSubscriptionActivitiesService < BaseService
    Result = BaseResult

    def call
      # NOTE: If we need to handle different delays per organization, this would be done here.
      #     This is why it's a dedicated service and not just done in the job

      Organization.all.pluck(:id).each do |organization_id|
        ProcessOrganizationSubscriptionActivitiesJob.perform_later(organization_id)
      end

      result
    end
  end
end
