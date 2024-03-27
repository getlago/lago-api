# frozen_string_literal: true

class AddPreciseAmountsToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    change_table :credit_notes, bulk: true do |t|
      t.decimal :precise_coupons_adjustment_amount_cents,
        precision: 30,
        scale: 5,
        null: false,
        default: 0

      t.decimal :precise_vat_amount_cents,
        precision: 30,
        scale: 5,
        null: false,
        default: 0
    end
  end
end
