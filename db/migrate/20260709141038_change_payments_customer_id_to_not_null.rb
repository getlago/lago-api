# frozen_string_literal: true

class ChangePaymentsCustomerIdToNotNull < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    change_column_null :payments, :customer_id, false
  end
end
