# frozen_string_literal: true

class AddAccountTypeToCustomers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :customers, :account_type, :string, default: 'customer'
    add_index :customers, :account_type, algorithm: :concurrently
  end
end
