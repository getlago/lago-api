# frozen_string_literal: true

class ConvertUnitAmountCentsToDecimal < ActiveRecord::Migration[7.0]
  def up
    change_column :fees, :unit_amount_cents, :decimal, precision: 30, scale: 5, null: false
  end

  def down
    change_column :fees, :unit_amount_cents, :bigint, null: false, default: 0
  end
end
