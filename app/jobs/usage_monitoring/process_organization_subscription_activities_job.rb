# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module UsageMonitoring
  class ProcessOrganizationSubscriptionActivitiesJob < ApplicationJob
    queue_as do
      organization_id = arguments.first
      if Utils::DedicatedWorkerConfig.enabled_for?(organization_id)
        Utils::DedicatedWorkerConfig::DEDICATED_ALERTS_QUEUE
      else
        :default
      end
    end

    unique :until_executed, on_conflict: :log

    def perform(organization_id)
      return unless License.premium?

      organization = Organization.find(organization_id)
      UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService.call!(organization:)
    end
  end
end
