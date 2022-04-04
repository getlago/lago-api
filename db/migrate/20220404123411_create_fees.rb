# frozen_string_literal: true

class CreateFees < ActiveRecord::Migration[7.0]
  def change
    create_table :fees, type: :uuid do |t|
      t.references :invoice, type: :uuid, foreign_key: true, index: true
      t.references :charge, type: :uuid, foreign_key: true, index: true
      t.references :subscription, type: :uuid, foreign_key: true, index: true

      t.integer :amount_cents, null: false, limit: 8
      t.string :amount_currency, null: false
      t.integer :vat_cents, null: false, limit: 8
      t.string :vat_currency, null: false
      t.float :vat_rate

      t.timestamps
    end
  end
end
