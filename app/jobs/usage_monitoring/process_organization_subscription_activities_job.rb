# frozen_string_literal: true

module UsageMonitoring
  class ProcessOrganizationSubscriptionActivitiesJob < ApplicationJob
    unique :until_executed, on_conflict: :log

    def perform(organization_id)
      return unless License.premium?

      organization = Organization.find(organization_id)
      result = UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService.call!(organization:)

      if result.nb_jobs_enqueued > 0
        Rails.logger.info(
          "[#{organization.id}] ProcessOrganizationSubscriptionActivitiesService enqueued #{result.nb_jobs_enqueued} jobs"
        )
      end
    end
  end
end
