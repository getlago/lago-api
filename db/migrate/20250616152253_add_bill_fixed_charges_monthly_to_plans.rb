# frozen_string_literal: true

class AddBillFixedChargesMonthlyToPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :plans, :bill_fixed_charges_monthly, :boolean
  end
end
