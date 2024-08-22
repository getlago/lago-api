# frozen_string_literal: true

class AddRefundFieldsToCreditNotes < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :credit_notes, bulk: true do |t|
        t.bigint :refund_amount_cents, null: false, default: 0
        t.string :refund_amount_currency
        t.integer :refund_status
      end
      change_column :credit_notes, :credit_status, :integer, null: true, default: :null

      change_table :credit_note_items, bulk: true do |t|
        t.bigint :refund_amount_cents, null: false, default: 0
        t.string :refund_amount_currency
      end
    end
  end

  def down
    change_table :credit_notes, bulk: true do |t|
      t.remove :refund_amount_cents
      t.remove :refund_amount_currency
      t.remove :refund_status
    end
    change_column :credit_notes, :credit_status, :integer, null: false, default: 0

    change_table :credit_note_items, bulk: true do |t|
      t.remove :refund_amount_cents
      t.remove :refund_amount_currency
    end
  end
end
