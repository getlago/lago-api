# frozen_string_literal: true

class CreateRecurringAggregationSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :recurring_aggregation_snapshots, id: :uuid, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid, index: false
      t.references :subscription, null: false, foreign_key: true, type: :uuid, index: false
      t.references :charge, null: false, foreign_key: true, type: :uuid, index: false
      t.references :charge_filter, null: true, foreign_key: true, type: :uuid, index: false
      t.references :billable_metric, null: false, foreign_key: true, type: :uuid, index: false

      t.jsonb :grouped_by, null: false, default: {}
      t.datetime :to_datetime, null: false
      t.datetime :watermark, null: false
      t.decimal :units, null: false, default: 0

      t.timestamps
    end
  end
end
