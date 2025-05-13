# frozen_string_literal: true

class AddVoidedAtToAppliedCoupons < ActiveRecord::Migration[8.0]
  def change
    add_column :applied_coupons, :voided_at, :datetime
  end
end
