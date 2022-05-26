# frozen_string_literal: true

class ChangeIndexOnAppliedCoupons < ActiveRecord::Migration[7.0]
  def change
    remove_index :applied_coupons, %i[coupon_id customer_id]
    add_index :applied_coupons, %i[coupon_id customer_id], unique: true, where: 'applied_coupons.status = 0'
  end
end
