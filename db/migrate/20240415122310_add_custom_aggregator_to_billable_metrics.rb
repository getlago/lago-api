# frozen_string_literal: true

class AddCustomAggregatorToBillableMetrics < ActiveRecord::Migration[7.0]
  def change
    add_column :billable_metrics, :custom_aggregator, :text
  end
end
