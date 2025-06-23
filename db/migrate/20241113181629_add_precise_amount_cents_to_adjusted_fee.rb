# frozen_string_literal: true

class AddPreciseAmountCentsToAdjustedFee < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      change_table :adjusted_fees, bulk: true do |t|
        t.decimal :unit_precise_amount_cents, precision: 40, scale: 15, default: "0.0", null: false
      end
    end
  end
end
