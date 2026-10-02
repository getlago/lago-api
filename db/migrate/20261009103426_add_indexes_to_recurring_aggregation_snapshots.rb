# frozen_string_literal: true

class AddIndexesToRecurringAggregationSnapshots < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # The unique index leads with subscription_id and also serves the latest-snapshot lookup,
  # so neither subscription_id nor charge_id gets its own index.
  INDEXES = [
    {
      columns: [:subscription_id, :charge_id, :charge_filter_id, :grouped_by, :to_datetime],
      name: :idx_recurring_aggregation_snapshots_unique,
      options: {unique: true, nulls_not_distinct: true}
    },
    {columns: :organization_id, name: :index_recurring_aggregation_snapshots_on_organization_id},
    {columns: :charge_filter_id, name: :index_recurring_aggregation_snapshots_on_charge_filter_id},
    {columns: :billable_metric_id, name: :index_recurring_aggregation_snapshots_on_billable_metric_id}
  ].freeze

  def up
    INDEXES.each do |index|
      # A failed concurrent build leaves an invalid index behind, which `if_not_exists`
      # would then keep: drop it so that a retry builds the index again.
      if index_exists?(:recurring_aggregation_snapshots, nil, name: index[:name], valid: false)
        remove_index :recurring_aggregation_snapshots, name: index[:name], algorithm: :concurrently
      end

      add_index :recurring_aggregation_snapshots,
        index[:columns],
        name: index[:name],
        algorithm: :concurrently,
        if_not_exists: true,
        **index.fetch(:options, {})
    end
  end

  def down
    INDEXES.each do |index|
      remove_index :recurring_aggregation_snapshots, name: index[:name], algorithm: :concurrently, if_exists: true
    end
  end
end
