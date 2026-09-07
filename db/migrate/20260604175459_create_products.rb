# frozen_string_literal: true

class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_enum :product_type, %w[usage fixed]

    create_table :products, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid
      t.references :product_category, null: true, foreign_key: true, type: :uuid
      t.references :billable_metric, null: true, foreign_key: true, type: :uuid
      t.references :add_on, null: true, foreign_key: true, type: :uuid
      t.references :charge, null: true, foreign_key: true, type: :uuid

      t.enum :product_type, enum_type: :product_type, null: false

      t.string :code, null: false
      t.string :name, null: false
      t.string :invoice_display_name
      t.text :description

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
