# frozen_string_literal: true

class CreatePlanProductItems < ActiveRecord::Migration[8.0]
  def change
    create_table :plan_product_items, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :plan, null: false, foreign_key: true, type: :uuid
      t.references :rate_card, null: false, foreign_key: true, type: :uuid

      t.decimal :units, precision: 30, scale: 10

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:plan_id, :rate_card_id],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_plan_product_items_on_plan_id_and_rate_card_id"
    end
  end
end
