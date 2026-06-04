# frozen_string_literal: true

class CreatePlanProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :plan_products, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :plan, null: false, foreign_key: true, type: :uuid
      t.references :product, null: false, foreign_key: true, type: :uuid

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:plan_id, :product_id],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_plan_products_on_plan_id_and_product_id"
    end
  end
end
