# frozen_string_literal: true

module UsageMonitoring
  class ProcessOrganizationSubscriptionActivitiesJob < ApplicationJob
    queue_as do
      organization_id = arguments.first
      if Utils::DedicatedWorkerConfig.enabled_for?(organization_id)
        Utils::DedicatedWorkerConfig::DEDICATED_ALERTS_QUEUE
      elsif ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"])
        :alerts
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
