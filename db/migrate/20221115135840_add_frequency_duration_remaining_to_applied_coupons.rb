# frozen_string_literal: true

class AddFrequencyDurationRemainingToAppliedCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :applied_coupons, :frequency_duration_remaining, :integer
    remove_index :applied_coupons, column: %i[coupon_id customer_id]
  end
end
