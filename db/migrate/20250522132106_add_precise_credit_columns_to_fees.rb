# frozen_string_literal: true

class AddPreciseCreditColumnsToFees < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      change_table :fees, bulk: true do |t|
        t.decimal :precise_progressive_credits_amount_cents, precision: 30, scale: 5, null: false, default: 0
        t.decimal :precise_credit_notes_amount_cents, precision: 30, scale: 5, null: false, default: 0
      end
    end
  end
end
