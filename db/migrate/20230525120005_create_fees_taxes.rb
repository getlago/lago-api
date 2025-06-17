# frozen_string_literal: true

class CreateFeesTaxes < ActiveRecord::Migration[7.0]
  def change
    create_table :fees_taxes, id: :uuid do |t|
      t.references :fee, type: :uuid, null: false, foreign_key: true, index: true
      t.references :tax, type: :uuid, null: false, foreign_key: true, index: true

      t.string :tax_description
      t.string :tax_code, null: false
      t.string :tax_name, null: false
      t.float :tax_rate, null: false, default: 0.0

      t.bigint :amount_cents, null: false, default: 0
      t.string :amount_currency, null: false

      t.timestamps
    end
  end
end
