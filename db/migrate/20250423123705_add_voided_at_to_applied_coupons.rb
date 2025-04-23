# frozen_string_literal: true

class AddVoidedAtToAppliedCoupons < ActiveRecord::Migration[7.2]
  def change
    add_column :applied_coupons, :voided_at, :datetime
  end
end
