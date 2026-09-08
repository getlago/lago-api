# frozen_string_literal: true

class ValidatePaymentsCustomerIdNullConstraint < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_check_constraint :payments, name: "payments_customer_id_null"
  end
end
