# frozen_string_literal: true

class CreateUsageBuckets15m < ActiveRecord::Migration[8.0]
  def change
    options = <<-SQL
      ReplacingMergeTree(ver, is_deleted)
      PARTITION BY toYYYYMM(bucket)
      ORDER BY (
        organization_id,
        subscription_id,
        charge_id,
        charge_filter_id,
        grouped_by,
        bucket
      )
    SQL

    create_table :usage_buckets_15m, id: false, options: do |t|
      t.datetime :bucket, null: false, precision: 3
      t.string :organization_id, null: false
      t.string :subscription_id, null: false
      t.string :customer_id, null: false
      t.string :plan_id
      t.string :code, null: false
      t.string :target_wallet_code
      t.string :charge_id, null: false
      t.string :charge_filter_id, null: false
      t.string :grouped_by, null: false
      t.string :aggregation_type, null: false
      t.integer :events_count, null: false, limit: 8, unsigned: false
      t.decimal :units, null: false, precision: 38, scale: 26
      t.datetime :last_event_at, null: false, precision: 3
      t.datetime :last_ingested_at, null: false, precision: 3
      t.integer :is_deleted, null: false, limit: 1, default: 0
      t.column :ver, "DateTime64(3) MATERIALIZED now64(3)", null: false
    end
  end
end
