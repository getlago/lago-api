# frozen_string_literal: true

class CreateAddOns < ActiveRecord::Migration[7.0]
  def change
    create_table :add_ons, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true

      t.string :name, null: false
      t.string :code, null: false
      t.string :description, null: true

      t.bigint :amount_cents, null: false
      t.string :amount_currency, null: false

      t.index %i[organization_id code], unique: true

      t.timestamps
    end
  end
end
