# frozen_string_literal: true

class AddCouponTypeAndPercentageRateToCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :coupons, :coupon_type, :integer, null: false, default: 0
    add_column :coupons, :percentage_rate, :decimal, precision: 10, scale: 5
    change_column_null :coupons, :amount_cents, true
    change_column_null :coupons, :amount_currency, true

    add_column :applied_coupons, :percentage_rate, :decimal, precision: 10, scale: 5
    change_column_null :applied_coupons, :amount_cents, true
    change_column_null :applied_coupons, :amount_currency, true
  end
end


