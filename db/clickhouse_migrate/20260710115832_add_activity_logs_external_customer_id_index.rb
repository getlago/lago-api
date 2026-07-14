# frozen_string_literal: true

class AddActivityLogsExternalCustomerIdIndex < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute "ALTER TABLE activity_logs ADD INDEX IF NOT EXISTS idx_external_customer_id external_customer_id TYPE bloom_filter(0.001) GRANULARITY 1"
      execute "ALTER TABLE activity_logs MATERIALIZE INDEX idx_external_customer_id"
    end
  end

  def down
    safety_assured do
      execute "ALTER TABLE activity_logs DROP INDEX IF EXISTS idx_external_customer_id"
    end
  end
end
