# frozen_string_literal: true

class AddTriggeredAtIndexToTriggeredAlerts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = "index_usage_monitoring_triggered_alerts_on_triggered_at"

  def up
    if index_exists?(:usage_monitoring_triggered_alerts, nil, name: INDEX_NAME, valid: false)
      remove_index :usage_monitoring_triggered_alerts, name: INDEX_NAME, algorithm: :concurrently
    end

    add_index :usage_monitoring_triggered_alerts, :triggered_at,
      algorithm: :concurrently,
      if_not_exists: true,
      name: INDEX_NAME
  end

  def down
    remove_index :usage_monitoring_triggered_alerts, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
