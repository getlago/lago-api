# frozen_string_literal: true

class CreateRatePhases < ActiveRecord::Migration[8.0]
  def change
    create_table :rate_phases, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :plan_product_item, null: true, foreign_key: true, type: :uuid
      t.references :subscription_product_item, null: true, foreign_key: true, type: :uuid

      t.integer :position, null: false
      t.integer :billing_interval_cycle_count

      # rate_override_id ships now but is only populated in v2 (rate_overrides
      # does not exist yet), so no foreign key is declared.
      t.uuid :rate_override_id

      t.datetime :deleted_at

      t.timestamps

      t.index :deleted_at
      t.index [:plan_product_item_id, :position],
        unique: true,
        where: "plan_product_item_id IS NOT NULL AND deleted_at IS NULL",
        name: "index_rate_phases_on_plan_product_item_id_and_position"
      t.index [:subscription_product_item_id, :position],
        unique: true,
        where: "subscription_product_item_id IS NOT NULL AND deleted_at IS NULL",
        name: "index_rate_phases_on_sub_product_item_id_and_position"

      t.check_constraint "(plan_product_item_id IS NULL) <> (subscription_product_item_id IS NULL)",
        name: "rate_phases_exactly_one_parent"
    end
  end
end
