# frozen_string_literal: true

class CreateProductItems < ActiveRecord::Migration[8.0]
  def change
    create_enum :product_item_type, %w[usage fixed]

    create_table :product_items, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product, null: true, foreign_key: true, type: :uuid
      t.references :billable_metric, null: true, foreign_key: true, type: :uuid
      t.references :add_on, null: true, foreign_key: true, type: :uuid
      t.references :charge, null: true, foreign_key: true, type: :uuid

      t.enum :item_type, enum_type: :product_item_type, null: false

      t.string :code, null: false
      t.string :name, null: false
      t.string :invoice_display_name
      t.text :description

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:product_id, :code],
        unique: true,
        where: "product_id IS NOT NULL AND deleted_at IS NULL",
        name: "index_product_items_on_product_id_and_code"
      t.index [:organization_id, :code],
        unique: true,
        where: "product_id IS NULL AND deleted_at IS NULL",
        name: "index_standalone_product_items_on_organization_id_and_code"
    end
  end
end
