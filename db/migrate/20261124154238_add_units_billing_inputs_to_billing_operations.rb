# frozen_string_literal: true

class AddUnitsBillingInputsToBillingOperations < ActiveRecord::Migration[8.1]
  def change
    add_column :billing_operations, :units_before, :decimal, if_not_exists: true
    add_column :billing_operations, :units_after, :decimal, if_not_exists: true
  end
end
