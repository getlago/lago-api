# frozen_string_literal: true

class AddAccountTypeToCustomers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    create_enum "account_type", ["customer", "partner"]

    add_column :customers, :account_type, :enum, enum_type: "account_type", default: "customer", null: false
    add_index :customers, :account_type, algorithm: :concurrently
  end
end
