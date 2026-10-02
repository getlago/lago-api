# frozen_string_literal: true

class CreateRecurringAggregationSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_aggregation_snapshots, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      # Covered by the unique index, which leads with subscription_id
      t.references :subscription, null: false, foreign_key: true, type: :uuid, index: false
      t.references :charge, null: false, foreign_key: true, type: :uuid, index: false
      t.references :charge_filter, null: true, foreign_key: true, type: :uuid
      t.references :billable_metric, null: false, foreign_key: true, type: :uuid

      t.jsonb :grouped_by, null: false, default: {}
      t.datetime :to_datetime, null: false
      t.datetime :watermark, null: false
      t.decimal :units, null: false, default: 0

      t.timestamps

      t.index [:subscription_id, :charge_id, :charge_filter_id, :grouped_by, :to_datetime],
        unique: true,
        nulls_not_distinct: true,
        name: "idx_recurring_aggregation_snapshots_unique"
    end
  end
end
