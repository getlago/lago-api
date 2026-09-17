# frozen_string_literal: true

module UsageMonitoring
  class ProcessOrganizationSubscriptionActivitiesJob < ApplicationJob
    queue_as do
      Utils::DedicatedWorkerConfig.queue_for(
        arguments.first,
        dedicated: Utils::DedicatedWorkerConfig::DEDICATED_ALERTS_QUEUE,
        default: ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"]) ? :alerts : :default
      )
    end

    unique :until_executed, on_conflict: :log

    def perform(organization_id)
      return unless License.premium?

      organization = Organization.find(organization_id)
      UsageMonitoring::ProcessOrganizationSubscriptionActivitiesService.call!(organization:)
    end
  end
end
