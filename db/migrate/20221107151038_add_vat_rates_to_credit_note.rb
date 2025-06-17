# frozen_string_literal: true

class AddVatRatesToCreditNote < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :credit_notes, bulk: true do |t|
        t.bigint :credit_vat_amount_cents, default: 0, null: false
        t.string :credit_vat_amount_currency

        t.bigint :refund_vat_amount_cents, default: 0, null: false
        t.string :refund_vat_amount_currency

        t.bigint :vat_amount_cents, default: 0, null: false
        t.string :vat_amount_currency
      end
    end
  end
end
