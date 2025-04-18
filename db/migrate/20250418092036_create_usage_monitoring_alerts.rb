# frozen_string_literal: true

class CreateUsageMonitoringAlerts < ActiveRecord::Migration[7.2]
  def change
    create_table :usage_monitoring_alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.string :subscription_external_id, null: false, index: true
      t.references :charge, type: :uuid, foreign_key: true, null: true, index: true # TODO: Is index needed?
      t.string :alert_type, null: false # Rails STI
      t.numeric :previous_value, precision: 30, scale: 5, null: false, default: 0
      t.datetime :last_processed_at
      t.string :code
      t.datetime :deleted_at
      t.timestamps

      t.index %w[subscription_external_id organization_id alert_type],
        unique: true,
        name: "idx_alerts_unique_per_type_per_customer",
        where: "(charge_id IS NULL AND deleted_at IS NULL)"
      t.index %w[subscription_external_id organization_id alert_type charge_id],
        unique: true,
        name: "idx_alerts_unique_per_type_per_customer_with_charge",
        where: "(charge_id IS NOT NULL AND deleted_at IS NULL)"
    end

    create_table :usage_monitoring_alert_thresholds, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.references :usage_monitoring_alert, type: :uuid, foreign_key: true, null: false, index: true
      t.numeric :value, precision: 30, scale: 5, null: false
      t.string :code
      t.timestamps
    end

    create_table :usage_monitoring_triggered_alerts, id: :uuid do |t|
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.references :usage_monitoring_alert, type: :uuid, foreign_key: true, null: false, index: true
      t.references :subscription, type: :uuid, foreign_key: true, null: false, index: true

      t.numeric :current_value, precision: 30, scale: 5, null: false
      t.numeric :previous_value, precision: 30, scale: 5, null: false
      t.jsonb :crossed_thresholds, default: {}

      t.datetime :triggered_at, null: false
      t.timestamps
    end

    # NOTICE THE PRIMARY KEY IS BIGSERIAL 😎
    create_table :usage_monitoring_subscription_activities, id: :bigserial do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: true
      t.references :subscription, type: :uuid, foreign_key: true, null: false, index: {
        unique: true, name: :idx_subscription_unique
      }
      t.datetime :inserted_at, default: -> { "CURRENT_TIMESTAMP" }, null: false
      t.boolean :enqueued, default: false, null: false
    end
  end
end
