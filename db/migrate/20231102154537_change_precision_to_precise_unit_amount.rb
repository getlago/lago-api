# frozen_string_literal: true

class ChangePrecisionToPreciseUnitAmount < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :fees, bulk: true do |t|
        t.change :precise_unit_amount, :decimal, precision: 30, scale: 15, null: false, default: '0.0'
      end
    end
  end

  def down
    change_table :fees, bulk: true do |t|
      t.change :precise_unit_amount, :decimal, precision: 30, scale: 5, null: false, default: '0.0'
    end
  end
end
