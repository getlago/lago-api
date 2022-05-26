# frozen_string_literal: true

class AddTerminatedAtToAppliedCoupons < ActiveRecord::Migration[7.0]
  def change
    add_column :applied_coupons, :terminated_at, :timestamp, null: true
  end
end
