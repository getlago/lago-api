# frozen_string_literal: true

module UsageMonitoring
  class ProcessLifetimeUsageAlertJob < ApplicationJob
    unique :until_executed, on_conflict: :log
    queue_as do
      Utils::DedicatedWorkerConfig.queue_for(
        arguments.first[:subscription]&.organization_id,
        dedicated: Utils::DedicatedWorkerConfig::DEDICATED_ALERTS_QUEUE,
        default: ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_ALERTS"]) ? :alerts : :default
      )
    end

    def perform(alert:, subscription:)
      ProcessLifetimeUsageAlertService.call!(alert:, subscription:)
    end

    private

    def lock_key_arguments
      [arguments.first[:alert]]
    end
  end
end
