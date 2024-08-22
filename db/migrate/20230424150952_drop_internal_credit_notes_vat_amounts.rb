# frozen_string_literal: true

class DropInternalCreditNotesVatAmounts < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :credit_notes, bulk: true do |t|
        t.remove :credit_vat_amount_cents
        t.remove :credit_vat_amount_currency
        t.remove :refund_vat_amount_cents
        t.remove :refund_vat_amount_currency
      end
    end
  end

  def down
    change_table :credit_notes, bulk: true do |t|
      t.bigint :credit_vat_amount_cents, null: false, default: 0
      t.string :credit_vat_amount_currency
      t.bigint :refund_vat_amount_cents, null: false, default: 0
      t.string :refund_vat_amount_currency
    end

    execute <<-SQL
    UPDATE credit_notes
      SET credit_vat_amount_currency = total_amount_currency,
      refund_vat_amount_currency = total_amount_currency
    SQL
  end
end
