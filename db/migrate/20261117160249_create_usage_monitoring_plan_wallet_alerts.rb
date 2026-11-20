# frozen_string_literal: true

class CreateUsageMonitoringPlanWalletAlerts < ActiveRecord::Migration[8.1]
  def change
    create_enum :usage_monitoring_plan_wallet_alert_alert_type, %w[balance ongoing_balance]

    create_table :usage_monitoring_plan_wallet_alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: {name: :idx_plan_wallet_alerts_organization_id}
      t.references :plan_wallet, type: :uuid, null: false, foreign_key: true, index: false
      t.enum :alert_type, enum_type: :usage_monitoring_plan_wallet_alert_alert_type, null: false
      t.string :code, null: false
      t.string :name
      t.timestamps

      t.index %i[plan_wallet_id alert_type], unique: true, name: :idx_plan_wallet_alerts_alert_type_unique
      t.index %i[plan_wallet_id code], unique: true, name: :idx_plan_wallet_alerts_code_unique
    end
  end
end
