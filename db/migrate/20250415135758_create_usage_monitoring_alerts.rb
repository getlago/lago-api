# frozen_string_literal: true

class CreateUsageMonitoringAlerts < ActiveRecord::Migration[7.2]
  def change
    create_table :usage_monitoring_alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.references :plan, type: :uuid, foreign_key: true, null: true, index: true
      t.string :subscription_external_id, index: true
      t.references :billable_metric, type: :uuid, foreign_key: true, null: true, index: true # TODO: Is index needed?
      t.string :alert_type, null: false # Rails STI
      t.string :code
      t.datetime :deleted_at
      t.timestamps
    end

    create_table :usage_monitoring_alert_thresholds, id: :uuid do |t|
      t.references :usage_monitoring_alerts, type: :uuid, foreign_key: true, null: false, index: true
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.numeric :value, precision: 30, scale: 5, null: false
      t.string :code
      t.timestamps
    end
  end
end
