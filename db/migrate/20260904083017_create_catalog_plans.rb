# frozen_string_literal: true

class CreateCatalogPlans < ActiveRecord::Migration[8.0]
  def change
    create_table :catalog_plans, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true

      t.string :name, null: false
      t.string :code, null: false
      t.string :invoice_display_name
      t.string :description
      t.string :currency, null: false

      t.datetime :deleted_at

      t.timestamps
    end

    add_index :catalog_plans, %i[organization_id code],
      unique: true,
      where: "deleted_at IS NULL",
      name: "index_catalog_plans_on_organization_id_and_code"
    add_index :catalog_plans, :deleted_at
  end
end
