# frozen_string_literal: true

class AddPreciseCreditColumnsToFees < ActiveRecord::Migration[8.0]
  def change
    add_column :fees, :precise_progressive_credits_amount_cents, :decimal, precision: 30, scale: 5, null: false, default: 0
    add_column :fees, :precise_credit_notes_amount_cents, :decimal, precision: 30, scale: 5, null: false, default: 0
  end
end
