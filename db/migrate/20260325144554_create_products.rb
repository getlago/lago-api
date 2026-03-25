# frozen_string_literal: true

class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.string :code, null: false
      t.string :name, null: false
      t.string :description
      t.string :invoice_display_name
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :products, :deleted_at
    add_index :products, [:organization_id, :code], unique: true, where: "deleted_at IS NULL"
  end
end
