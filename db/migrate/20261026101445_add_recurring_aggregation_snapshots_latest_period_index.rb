# frozen_string_literal: true

# RecurringAggregationSnapshots::FetchService looks up the latest period of a charge's default
# bucket before a date, and the unique index cannot serve it: `grouped_by` sits before
# `to_datetime`, so every past period and group of the bucket would be read and sorted.
class AddRecurringAggregationSnapshotsLatestPeriodIndex < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
    # would then keep: drop it so that a retry builds the index again.
    if index_exists?(:recurring_aggregation_snapshots, nil, name: :index_recurring_aggregation_snapshots_by_period, valid: false)
      remove_index :recurring_aggregation_snapshots, name: :index_recurring_aggregation_snapshots_by_period, algorithm: :concurrently
    end

    # strong_migrations doubts non-unique indexes past three columns. The lookup needs all four:
    # three equality filters, then the date that both bounds and orders it.
    safety_assured do
      add_index :recurring_aggregation_snapshots,
        [:subscription_id, :charge_id, :charge_filter_id, :to_datetime],
        name: :index_recurring_aggregation_snapshots_by_period,
        algorithm: :concurrently,
        if_not_exists: true
    end
  end

  def down
    remove_index :recurring_aggregation_snapshots,
      name: :index_recurring_aggregation_snapshots_by_period,
      algorithm: :concurrently,
      if_exists: true
  end
end
