# frozen_string_literal: true

class ChangesCreditNoteItemsColumns < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :credit_note_items, bulk: true do |t|
        t.remove :refund_amount_cents
        t.remove :refund_amount_currency

        t.rename :credit_amount_cents, :amount_cents
        t.rename :credit_amount_currency, :amount_currency
      end
    end
  end

  def down
    change_table :credit_note_items, bulk: true do |t|
      t.bigint :refund_amount_cents, null: false, default: 0
      t.string :refund_amount_currency, null: true

      t.rename :amount_cents, :credit_amount_cents
      t.rename :amount_currency, :credit_amount_currency
    end
  end
end
