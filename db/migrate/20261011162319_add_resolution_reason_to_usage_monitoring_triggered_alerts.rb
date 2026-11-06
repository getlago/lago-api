# frozen_string_literal: true

class AddResolutionReasonToUsageMonitoringTriggeredAlerts < ActiveRecord::Migration[8.0]
  def change
    create_enum :usage_monitoring_triggered_alert_resolution_reasons, %w[recovered threshold_updated threshold_removed]

    add_column :usage_monitoring_triggered_alerts, :resolution_reason, :enum,
      enum_type: :usage_monitoring_triggered_alert_resolution_reasons,
      if_not_exists: true
  end
end
