# frozen_string_literal: true

module UsageMonitoring
  class ProcessLifetimeUsageAlertJob < ApplicationJob
    unique :until_executed, on_conflict: :log
    queue_as :default

    def perform(alert_id)
      alert = UsageMonitoring::Alert.find(alert_id)
      ProcessLifetimeUsageAlertService.call!(alert:)
    end
  end
end
