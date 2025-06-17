# frozen_string_literal: true

class CreateCouponPlans < ActiveRecord::Migration[7.0]
  def change
    create_table :coupon_plans, id: :uuid do |t|
      t.references :coupon, type: :uuid, index: true, null: false, foreign_key: true
      t.references :plan, type: :uuid, index: true, null: false, foreign_key: true

      t.timestamps
    end

    add_column :coupons, :limited_plans, :boolean, default: false, null: false
  end
end
