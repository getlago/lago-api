# frozen_string_literal: true

class CreateUsageMonitoringContractAlerts < ActiveRecord::Migration[8.1]
  def change
    create_enum :usage_monitoring_contract_alert_alert_type, %w[usage_amount usage_units]

    create_table :usage_monitoring_contract_alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: false
      t.string :contract_external_id, null: false
      t.references :product, type: :uuid, foreign_key: true, index: false
      t.references :product_filter, type: :uuid, foreign_key: true, index: false
      t.enum :alert_type, enum_type: "usage_monitoring_contract_alert_alert_type", null: false
      t.enum :direction, enum_type: "usage_monitoring_alert_direction", null: false, default: "increasing"
      t.string :code, null: false
      t.string :name
      t.decimal :previous_value, precision: 30, scale: 5, null: false, default: 0
      t.jsonb :previous_windows, null: false, default: {}
      t.datetime :last_processed_at
      t.datetime :deleted_at
      t.timestamps

      t.index [:organization_id, :contract_external_id, :code],
        unique: true, where: "deleted_at IS NULL", name: :idx_contract_alerts_code_unique
      t.index [:organization_id, :contract_external_id, :alert_type, :product_id, :product_filter_id],
        unique: true, nulls_not_distinct: true, where: "deleted_at IS NULL", name: :idx_contract_alerts_scope_unique
    end
  end
end
