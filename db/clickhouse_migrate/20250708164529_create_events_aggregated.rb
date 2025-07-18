# frozen_string_literal: true

class CreateEventsAggregated < ActiveRecord::Migration[8.0]
  def change
    options = <<-SQL
    AggregatingMergeTree
    ORDER BY (
      organization_id,
      code,
      start_at,
      external_subscription_id,
      subscription_id,
      charge_id,
      charge_filter_id,
      --grouped_by
    )
    SQL

    create_table :events_aggregated, id: false, options: do |t|
      t.string :organization_id, null: false
      t.string :code, null: false
      t.datetime :start_at, null: false, precision: 3
      t.string :external_subscription_id, null: false
      t.string :subscription_id, null: false
      t.string :plan_id, null: false
      t.string :charge_id, null: false
      t.string :charge_filter_id, null: false, default: ""
      # t.string :grouped_by, map: true, null: false, default: -> { "map()" }
      # Multiple aggregation states for different charge models
      # Only one will be populated based on the charge's aggregation type
      t.column :sum_state, "AggregateFunction(sum, Decimal(38, 26))", null: false
      t.column :count_state, "AggregateFunction(count, UInt64)", null: false
      t.column :max_state, "AggregateFunction(max, Decimal(38, 26))", null: false
      # Latest aggregation using argMax - stores the latest value based on timestamp
      # argMax(value, timestamp) returns the value corresponding to the maximum timestamp
      t.column :latest_state, "AggregateFunction(argMax, Decimal(38, 26), DateTime64(3))", null: false
    end
  end
end
