# frozen_string_literal: true

class AddForeignKeyOnCustomerItAtPayments < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_foreign_key :payments, :customers, column: :customer_id, validate: false
  end
end
