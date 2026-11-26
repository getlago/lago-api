# frozen_string_literal: true

class CreateUsageMonitoringCatalogWalletTriggeredAlerts < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_monitoring_catalog_wallet_triggered_alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: {name: :idx_catalog_wallet_triggered_alerts_organization_id}
      # No foreign key: alerts are deleted for good, and the history keeps the alert id its webhooks carried
      t.references :catalog_wallet_alert, type: :uuid, null: false, foreign_key: false,
        index: {name: :idx_catalog_wallet_triggered_alerts_catalog_wallet_alert_id}
      t.references :catalog_wallet, type: :uuid, null: false, foreign_key: true, index: false
      t.string :alert_code, null: false
      t.string :alert_name
      t.enum :alert_type, enum_type: :usage_monitoring_catalog_wallet_alert_alert_type, null: false
      t.enum :kind, enum_type: :usage_monitoring_triggered_alert_kinds, null: false, default: "triggered"
      t.enum :resolution_reason, enum_type: :usage_monitoring_triggered_alert_resolution_reasons
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
