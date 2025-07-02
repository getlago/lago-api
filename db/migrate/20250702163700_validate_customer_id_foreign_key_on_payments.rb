# frozen_string_literal: true

class ValidateCustomerIdForeignKeyOnPayments < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :payments, :customers, column: :customer_id
  end
end
