# frozen_string_literal: true

class AddCustomerTypeToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :customer_type, :integer, default: nil, null: true
  end
end
