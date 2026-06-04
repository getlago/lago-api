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

      t.index :deleted_at
      t.index [:organization_id, :code],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_products_on_organization_id_and_code"
    end
  end
end
