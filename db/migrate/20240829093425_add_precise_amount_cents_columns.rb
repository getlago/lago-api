# frozen_string_literal: true

class AddPreciseAmountCentsColumns < ActiveRecord::Migration[7.1]
  def change
    safety_assured do
      change_table :fees, bulk: true do |t|
        t.decimal :precise_amount_cents, precision: 40, scale: 15, default: '0.0', null: false
        t.decimal :taxes_precise_amount_cents, precision: 40, scale: 15, default: '0.0', null: false
      end

      change_table :fees_taxes, bulk: true do |t|
        t.decimal :precise_amount_cents, precision: 40, scale: 15, default: '0.0', null: false
      end
    end
  end
end
