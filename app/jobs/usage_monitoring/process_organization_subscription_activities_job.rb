# frozen_string_literal: true

module UsageMonitoring
  class ProcessOrganizationSubscriptionActivitiesJob < ApplicationJob
    unique :until_executed, on_conflict: :log

    def perform(organization)
      return unless License.premium?

      result = UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService.call!(organization:)

      Rails.logger.info(
        "[#{organization.id}] ProcessOrganizationSubscriptionActivitiesService enqueued #{result.nb_jobs_enqueued} jobs"
      )
    end
  end
end
