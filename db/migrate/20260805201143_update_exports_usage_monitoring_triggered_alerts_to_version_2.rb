# frozen_string_literal: true

class UpdateExportsUsageMonitoringTriggeredAlertsToVersion2 < ActiveRecord::Migration[8.0]
  def change
    update_view :exports_usage_monitoring_triggered_alerts, version: 2, revert_to_version: 1
  end
end
