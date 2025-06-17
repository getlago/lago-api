# frozen_string_literal: true

class CreateTaxRates < ActiveRecord::Migration[7.0]
  def change
    create_table :tax_rates, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true

      t.string :description
      t.string :code, null: false
      t.string :name, null: false
      t.float :value, null: false, default: 0.0

      t.timestamps
    end

    add_index :tax_rates, [:code, :organization_id], unique: true
  end
end
