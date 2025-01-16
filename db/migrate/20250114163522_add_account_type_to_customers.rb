# frozen_string_literal: true

class AddAccountTypeToCustomers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    create_enum :customer_account_type, %w[customer partner]
    add_column :customers, :account_type, :enum, enum_type: "customer_account_type", default: "customer", null: false

    add_index :customers, :account_type, algorithm: :concurrently
  end
end
