# frozen_string_literal: true

class AddWalletCoverageToFees < ActiveRecord::Migration[8.1]
  def change
    add_column :fees, :precise_wallet_coverage_before_tax_amount_cents, :decimal,
      precision: 30, scale: 5, null: false, default: 0, if_not_exists: true
    add_column :fees, :precise_wallet_coverage_after_tax_amount_cents, :decimal,
      precision: 30, scale: 5, null: false, default: 0, if_not_exists: true
  end
end
