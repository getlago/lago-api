# frozen_string_literal: true

class CreateGroupKeys < ActiveRecord::Migration[8.0]
  def change
    create_enum :group_key_key_type, ["pricing", "presentation"]

    create_table :group_keys, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :charge, null: false, foreign_key: true, type: :uuid
      t.references :charge_filter, foreign_key: true, type: :uuid
      t.string :key, null: false
      t.enum :key_type, enum_type: :group_key_key_type, null: false
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :group_keys, :deleted_at
    add_index :group_keys, :charge_filter_id,
      where: "charge_filter_id IS NOT NULL",
      name: "index_group_keys_on_charge_filter_id_not_null"
    add_index :group_keys, [:charge_id, :charge_filter_id, :key, :key_type],
      unique: true, where: "deleted_at IS NULL",
      name: "index_group_keys_unique_active"
  end
end
