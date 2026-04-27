# frozen_string_literal: true

class CreatePlanProductsAndPlanProductItems < ActiveRecord::Migration[8.0]
  def change
    create_table :plan_products, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :plan, null: false, foreign_key: true, type: :uuid
      t.references :product, null: false, foreign_key: true, type: :uuid

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :plan_products, :deleted_at
    add_index :plan_products, [:plan_id, :product_id],
      unique: true,
      where: "deleted_at IS NULL",
      name: :idx_plan_products_on_plan_and_product

    create_table :plan_product_items, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :plan, null: false, foreign_key: true, type: :uuid
      t.references :product_item, null: false, foreign_key: true, type: :uuid

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :plan_product_items, :deleted_at
    add_index :plan_product_items, [:plan_id, :product_item_id],
      unique: true,
      where: "deleted_at IS NULL",
      name: :idx_plan_product_items_on_plan_and_product_item
  end
end
