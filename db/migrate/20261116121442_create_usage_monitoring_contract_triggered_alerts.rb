# frozen_string_literal: true

class CreateUsageMonitoringContractTriggeredAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_monitoring_contract_triggered_alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false
      t.references :contract_alert, type: :uuid, null: false, foreign_key: {to_table: :usage_monitoring_contract_alerts}
      t.references :contract, type: :uuid, foreign_key: true, null: false, index: false
      t.enum :kind, enum_type: "usage_monitoring_triggered_alert_kinds", null: false, default: "triggered"
      t.enum :resolution_reason, enum_type: "usage_monitoring_triggered_alert_resolution_reasons"
      t.decimal :current_value, precision: 30, scale: 5, null: false
      t.decimal :previous_value, precision: 30, scale: 5, null: false
      t.jsonb :crossed_thresholds, null: false
      t.jsonb :in_alarm_thresholds
      t.boolean :fully_resolved
      t.datetime :triggered_at, null: false
      t.timestamps
    end
  end
end
