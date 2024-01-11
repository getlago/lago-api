# frozen_string_literal: true

class CreateBillableMetricFilters < ActiveRecord::Migration[7.0]
  def change
    create_table :billable_metric_filters, id: :uuid do |t|
      t.references :billable_metric, null: false, foreign_key: true, type: :uuid
      t.string :key, null: false
      t.string :values, null: false, array: true, default: []

      t.timestamps

      t.datetime :deleted_at, index: true
    end
  end
end
