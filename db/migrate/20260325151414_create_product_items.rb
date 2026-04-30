# frozen_string_literal: true

class CreateProductItems < ActiveRecord::Migration[8.0]
  def change
    create_enum :product_item_type, %w[usage fixed subscription]

    create_table :product_items, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product, foreign_key: true, type: :uuid
      t.references :billable_metric, foreign_key: true, type: :uuid
      t.references :add_on, foreign_key: true, type: :uuid
      t.references :charge, foreign_key: true, type: :uuid

      t.enum :item_type, enum_type: :product_item_type, null: false
      t.string :code, null: false
      t.string :name
      t.string :invoice_display_name
      t.text :description
      t.string :grouping_key
      t.boolean :accepts_target_wallet

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :product_items, :deleted_at
    add_index :product_items, [:product_id, :code], unique: true, where: "deleted_at IS NULL"
  end
end
