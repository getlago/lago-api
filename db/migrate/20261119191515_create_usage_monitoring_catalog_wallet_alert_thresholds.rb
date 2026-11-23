# frozen_string_literal: true

class CreateUsageMonitoringCatalogWalletAlertThresholds < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_monitoring_catalog_wallet_alert_thresholds, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: {name: :idx_catalog_wallet_alert_thresholds_organization_id}
      t.references :plan_wallet_alert, type: :uuid,
        foreign_key: {to_table: :usage_monitoring_plan_wallet_alerts, on_delete: :cascade},
        index: {name: :idx_catalog_wallet_alert_thresholds_plan_wallet_alert_id, where: "plan_wallet_alert_id IS NOT NULL"}
      t.references :catalog_wallet_alert, type: :uuid,
        foreign_key: {to_table: :usage_monitoring_catalog_wallet_alerts, on_delete: :cascade},
        index: {name: :idx_catalog_wallet_alert_thresholds_catalog_wallet_alert_id, where: "catalog_wallet_alert_id IS NOT NULL"}
      t.decimal :value, precision: 30, scale: 5, null: false
      t.string :code
      t.boolean :recurring, null: false, default: false
      t.string :notify_on, array: true, null: false, default: ["triggered"]
      t.timestamps

      t.index %i[plan_wallet_alert_id recurring], unique: true, where: "recurring IS TRUE", name: :idx_catalog_wallet_alert_thresholds_plan_recurring_unique
      t.index %i[catalog_wallet_alert_id recurring], unique: true, where: "recurring IS TRUE", name: :idx_catalog_wallet_alert_thresholds_catalog_recurring_unique

      t.check_constraint "num_nonnulls(plan_wallet_alert_id, catalog_wallet_alert_id) = 1", name: :catalog_wallet_alert_thresholds_one_owner
      t.check_constraint "NOT recurring OR value > 0", name: :catalog_wallet_alert_thresholds_recurring_step_positive
    end
  end
end
