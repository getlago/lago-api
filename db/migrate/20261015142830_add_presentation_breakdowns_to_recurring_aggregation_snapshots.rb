# frozen_string_literal: true

class AddPresentationBreakdownsToRecurringAggregationSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :recurring_aggregation_snapshots, :presentation_breakdowns, :jsonb, null: false, default: [], if_not_exists: true
  end
end
