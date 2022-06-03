# frozen_string_literal: true

class AddBillChargesMonthlyToPlans < ActiveRecord::Migration[7.0]
  def change
    add_column :plans, :bill_charges_monthly, :boolean
  end
end
