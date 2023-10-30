# frozen_string_literal: true

class AddPreciseUnitAmountToFees < ActiveRecord::Migration[7.0]
  class Fee < ApplicationRecord
    monetize :unit_amount_cents, with_model_currency: :amount_currency
  end

  def up
    change_table :fees, bulk: true do |t|
      t.change :unit_amount_cents, :bigint, null: false, default: 0
    end
    add_column :fees, :precise_unit_amount, :decimal, precision: 30, scale: 5, null: false, default: '0.0'

    Fee.where.not(unit_amount_cents: 0).find_each do |f|
      f.update!(precise_unit_amount: f.unit_amount.to_f)
    end
  end

  def down
    change_table :fees, bulk: true do |t|
      t.change :unit_amount_cents, :decimal, precision: 30, scale: 5, null: false
    end
    remove_column :fees, :precise_unit_amount, :decimal
  end
end
