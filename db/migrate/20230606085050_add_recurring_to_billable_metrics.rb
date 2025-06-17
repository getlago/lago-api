# frozen_string_literal: true

class AddRecurringToBillableMetrics < ActiveRecord::Migration[7.0]
  def change
    add_column :billable_metrics, :recurring, :boolean, null: false, default: false
  end
end
