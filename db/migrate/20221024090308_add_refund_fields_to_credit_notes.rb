# frozen_string_literal: true

class AddRefundFieldsToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    change_table :credit_notes, bulk: true do |t|
      t.bigint :refund_amount_cents, null: false, default: 0
      t.string :refund_amount_currency
      t.integer :refund_status, null: false, default: 0
    end

    change_table :credit_note_items, bulk: true do |t|
      t.bigint :refund_amount_cents, null: false, default: 0
      t.string :refund_amount_currency
    end
  end
end
