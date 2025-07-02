# frozen_string_literal: true

class ValidateNotNullCheckOnCustomerIdForPayment < ActiveRecord::Migration[8.0]
  def up
    validate_check_constraint :payments, name: "payments_customer_id_null"
    change_column_null :payments, :customer_id, false
    remove_check_constraint :payments, name: "payments_customer_id_null"
  end

  def down
    add_check_constraint :payments, "customer_id IS NOT NULL", name: "payments_customer_id_null", validate: false
    change_column_null :payments, :customer_id, true
  end
end
