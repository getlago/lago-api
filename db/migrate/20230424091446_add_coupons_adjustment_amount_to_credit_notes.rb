# frozen_string_literal: true

class AddCouponsAdjustmentAmountToCreditNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :credit_notes, :coupons_adjustment_amount_cents, :bigint, null: false, default: 0
  end
end
