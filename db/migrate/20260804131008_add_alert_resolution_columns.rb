# frozen_string_literal: true

class AddAlertResolutionColumns < ActiveRecord::Migration[8.0]
  def change
    create_enum :usage_monitoring_triggered_alert_kinds, %w[triggered resolved seeded]

    add_column :usage_monitoring_alert_thresholds, :notify_on, :string, array: true, default: ["triggered"], null: false

    add_column :usage_monitoring_triggered_alerts, :kind, :enum,
      enum_type: :usage_monitoring_triggered_alert_kinds,
      default: "triggered",
      null: false
    add_column :usage_monitoring_triggered_alerts, :in_alarm_thresholds, :jsonb
    add_column :usage_monitoring_triggered_alerts, :fully_resolved, :boolean
  end
end
