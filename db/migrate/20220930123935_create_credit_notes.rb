# frozen_string_literal: true

class CreateCreditNotes < ActiveRecord::Migration[7.0]
  def change
    create_table :credit_notes, id: :uuid do |t|
      t.references :customer, type: :uuid, index: true, foreign_key: true, null: false
      t.references :invoice, type: :uuid, index: true, foreign_key: true, null: false
      t.integer :sequential_id, null: false
      t.string :number, null: false
      t.bigint :amount_cents, default: 0, null: false
      t.string :amount_currency, null: false
      t.integer :status, null: false, default: 0
      t.bigint :remaining_amount_cents, default: 0, null: false
      t.string :remaining_amount_currency, default: 0, null: false
      t.integer :reason, null: false
      t.string :file
      t.timestamps
    end
  end
end
