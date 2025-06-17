# frozen_String_literal: true

class RenameCreditNoteItems < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :credit_note_items, :amount_cents, :credit_amount_cents
      rename_column :credit_note_items, :amount_currency, :credit_amount_currency
    end
  end
end
