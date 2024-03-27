# frozen_string_literal: true

class AddWeightedIntervalToBillableMetric < ActiveRecord::Migration[7.0]
  def change
    create_enum :billable_metric_weighted_interval, %w[seconds]

    change_table :billable_metrics do |t|
      t.enum :weighted_interval, enum_type: "billable_metric_weighted_interval", null: true
    end
  end
end
