# frozen_string_literal: true

class CreateProductFilters < ActiveRecord::Migration[8.0]
  def change
    create_table :product_filters, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product, null: false, foreign_key: true, type: :uuid

      t.string :name, null: false
      t.string :code, null: false
      t.string :description
      t.string :invoice_display_name

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:product_id, :code],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_product_filters_on_product_id_and_code"
    end
  end
end
