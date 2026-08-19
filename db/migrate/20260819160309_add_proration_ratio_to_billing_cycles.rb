# frozen_string_literal: true

class AddProrationRatioToBillingCycles < ActiveRecord::Migration[8.0]
  def change
    add_column :billing_cycles, :proration_ratio, :decimal, precision: 30, scale: 10, null: false, default: 1
  end
end
