# frozen_string_literal: true

class CreateCreditNoteItems < ActiveRecord::Migration[7.0]
  def change
    create_table :credit_note_items, id: :uuid do |t|
      t.references :credit_note, type: :uuid, foreign_key: true, index: true, null: false
      t.references :fee, type: :uuid, foreign_key: true, index: true, null: false
      t.bigint :amount_cents, default: 0, null: false
      t.string :amount_currency, null: false
      t.timestamps
    end
  end
end
