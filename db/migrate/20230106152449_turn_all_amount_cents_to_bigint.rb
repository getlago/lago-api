# frozen_string_literal: true

class TurnAllAmountCentsToBigint < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_column :applied_add_ons, :amount_cents, :bigint, null: false
      change_column :applied_coupons, :amount_cents, :bigint, null: true
    end
  end

  def down
    change_column :applied_add_ons, :amount_cents, :integer, null: false
    change_column :applied_coupons, :amount_cents, :integer, null: true
  end
end
