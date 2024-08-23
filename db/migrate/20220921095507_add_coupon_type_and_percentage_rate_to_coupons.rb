# frozen_string_literal: true

class AddCouponTypeAndPercentageRateToCoupons < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :coupons, bulk: true do |t|
        t.integer :coupon_type, null: false, default: 0
        t.decimal :percentage_rate, precision: 10, scale: 5
      end

      change_column_null :coupons, :amount_cents, true
      change_column_null :coupons, :amount_currency, true

      change_table :applied_coupons, bulk: true do |t|
        t.decimal :percentage_rate, precision: 10, scale: 5
      end

      change_column_null :applied_coupons, :amount_cents, true
      change_column_null :applied_coupons, :amount_currency, true
    end
  end
end
