# frozen_string_literal: true

class CreateProductItemFilterValues < ActiveRecord::Migration[8.0]
  def change
    create_table :product_item_filter_values, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product_item_filter, null: false, foreign_key: true, type: :uuid
      t.references :billable_metric_filter, null: false, foreign_key: true, type: :uuid

      t.string :value, null: false

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:product_item_filter_id, :billable_metric_filter_id, :value],
        unique: true,
        where: "deleted_at IS NULL",
        name: "idx_pif_values_on_filter_metric_filter_and_value"
    end
  end
end
