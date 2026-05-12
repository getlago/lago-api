# frozen_string_literal: true

class AddNotNullToCouponCode < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL
        UPDATE coupons SET code = 'coupon-' || LEFT(id::text, 8) WHERE code IS NULL;
      SQL

      change_column_null :coupons, :code, false
    end
  end

  def down
    change_column_null :coupons, :code, true
  end
end
