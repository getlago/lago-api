# frozen_string_literal: true

class AddCouponTypeAndPercentageRateToCoupons < ActiveRecord::Migration[7.0]
  def change
    change_table :coupons, bulk: true do |t|
      t.integer :coupon_type, null: false, default: 0
      t.decimal :percentage_rate, precision: 10, scale: 5
      t.change :amount_cents, :bigint, null: true
      t.change :amount_currency, :string, null: true
    end

    change_table :applied_coupons, bulk: true do |t|
      t.decimal :percentage_rate, precision: 10, scale: 5
      t.change :amount_cents, :integer, null: true
      t.change :amount_currency, :string, null: true
    end
  end
end
