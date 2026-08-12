# frozen_string_literal: true

class CreateProductFilterValues < ActiveRecord::Migration[8.0]
  def change
    create_table :product_filter_values, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product_filter, null: false, foreign_key: true, type: :uuid
      t.references :billable_metric_filter, null: false, foreign_key: true, type: :uuid

      # NULL means the filter matches any value of the key (key-only selection)
      t.string :value

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      # NULLS NOT DISTINCT so two key-only rows (value IS NULL) for the same
      # key cannot coexist.
      t.index [:product_filter_id, :billable_metric_filter_id, :value],
        unique: true,
        where: "deleted_at IS NULL",
        nulls_not_distinct: true,
        name: "idx_pif_values_on_filter_metric_filter_and_value"
    end
  end
end
