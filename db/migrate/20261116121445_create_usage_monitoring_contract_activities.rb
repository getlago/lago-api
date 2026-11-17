# frozen_string_literal: true

class CreateUsageMonitoringContractActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_monitoring_contract_activities, id: :bigserial do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :organization, type: :uuid, foreign_key: true, null: false, index: false
      t.references :contract, type: :uuid, foreign_key: true, null: false, index: {
        unique: true, name: :idx_contract_activity_unique
      }
      t.boolean :enqueued, default: false, null: false
      t.datetime :inserted_at, default: -> { "CURRENT_TIMESTAMP" }, null: false
      t.datetime :enqueued_at

      t.index [:organization_id, :enqueued], name: :idx_contract_activities_enqueued_per_org
    end
  end
end
