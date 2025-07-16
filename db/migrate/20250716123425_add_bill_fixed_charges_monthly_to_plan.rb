# frozen_string_literal: true

class AddBillFixedChargesMonthlyToPlan < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :plans, :bill_fixed_charges_monthly, :boolean, default: false, null: false
    add_index :plans, :bill_fixed_charges_monthly, algorithm: :concurrently
  end
end
