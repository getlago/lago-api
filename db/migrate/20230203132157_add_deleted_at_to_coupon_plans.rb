# frozen_string_literal: true

class AddDeletedAtToCouponPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :coupon_plans, :deleted_at, :datetime
    safety_assured do
      add_index :coupon_plans, :deleted_at
    end
  end
end
