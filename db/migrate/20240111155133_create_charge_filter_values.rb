# frozen_string_literal: true

class CreateChargeFilterValues < ActiveRecord::Migration[7.0]
  def change
    create_table :charge_filter_values, id: :uuid do |t|
      t.references :charge_filter, null: false, foreign_key: true, type: :uuid, index: true
      t.references :billable_metric_filter, null: false, foreign_key: true, type: :uuid, index: true

      t.string :value, null: false

      t.timestamps
      t.datetime :deleted_at, index: true
    end
  end
end
