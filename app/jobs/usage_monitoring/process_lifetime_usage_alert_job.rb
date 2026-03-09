# frozen_string_literal: true

module UsageMonitoring
  class ProcessLifetimeUsageAlertJob < ApplicationJob
    unique :until_executed, on_conflict: :log

    def perform(alert_id)
      return unless License.premium?

      alert = UsageMonitoring::Alert.find(alert_id)
      ProcessLifetimeUsageAlertService.call!(alert:)
    end
  end
end
