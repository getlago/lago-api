# frozen_string_literal: true

class AddPreciseCouponsAmountCentsToFees < ActiveRecord::Migration[7.0]
  def change
    add_column :fees, :precise_coupons_amount_cents, :decimal, precision: 30, scale: 5, null: false, default: 0
    add_column :invoices_taxes, :fees_amount_cents, :bigint, null: false, default: 0
  end
end
