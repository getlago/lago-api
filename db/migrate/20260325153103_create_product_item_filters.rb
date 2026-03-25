# frozen_string_literal: true

class CreateProductItemFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :product_item_filters, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product_item, null: false, foreign_key: true, type: :uuid
      t.references :billable_metric_filter, null: false, foreign_key: true, type: :uuid

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :product_item_filters, :deleted_at
    add_index :product_item_filters, [:product_item_id, :billable_metric_filter_id],
      unique: true,
      where: "deleted_at IS NULL",
      name: :idx_product_item_filters_on_item_and_bm_filter

    create_table :product_item_filter_values, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product_item_filter, null: false, foreign_key: true, type: :uuid

      t.string :value, null: false

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :product_item_filter_values, :deleted_at
    add_index :product_item_filter_values, [:product_item_filter_id, :value],
      unique: true,
      where: "deleted_at IS NULL",
      name: :idx_product_item_filter_values_on_filter_and_value
  end
end
