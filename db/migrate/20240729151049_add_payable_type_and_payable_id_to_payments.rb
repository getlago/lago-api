# frozen_string_literal: true

class AddPayableTypeAndPayableIdToPayments < ActiveRecord::Migration[7.1]
  def change
    add_column :payments, :payable_type, :string, null: false, default: "Invoice"
    rename_column :payments, :invoice_id, :payable_id
  end
end
