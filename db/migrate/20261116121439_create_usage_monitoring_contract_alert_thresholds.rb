# frozen_string_literal: true

class CreateUsageMonitoringContractAlertThresholds < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_monitoring_contract_alert_thresholds, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false
      t.references :contract_alert, type: :uuid, null: false, foreign_key: {to_table: :usage_monitoring_contract_alerts}
      t.decimal :value, precision: 30, scale: 5, null: false
      t.string :code
      t.boolean :recurring, null: false, default: false
      t.string :notify_on, array: true, null: false, default: ["triggered"]
      t.timestamps

      t.index [:contract_alert_id, :recurring], unique: true, where: "recurring IS TRUE"
    end
  end
end
