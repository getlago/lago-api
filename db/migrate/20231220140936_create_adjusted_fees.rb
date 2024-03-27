# frozen_string_literal: true

class CreateAdjustedFees < ActiveRecord::Migration[7.0]
  def change
    create_table :adjusted_fees, id: :uuid do |t|
      t.references :fee, type: :uuid, null: true, index: true, foreign_key: true
      t.references :invoice, type: :uuid, null: false, index: true, foreign_key: true
      t.references :subscription, type: :uuid, null: true, foreign_key: true, index: true
      t.references :charge, type: :uuid, null: true, foreign_key: true, index: true

      t.string :invoice_display_name
      t.integer :fee_type
      t.boolean :adjusted_units, default: false, null: false
      t.boolean :adjusted_amount, default: false, null: false
      t.decimal :units, default: "0.0", null: false
      t.bigint :unit_amount_cents, null: false, default: 0
      t.jsonb :properties, null: false, default: {}

      t.timestamps
    end
  end
end
