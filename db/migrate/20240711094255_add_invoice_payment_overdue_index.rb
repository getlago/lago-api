# frozen_string_literal: true

class AddInvoicePaymentOverdueIndex < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :invoices, :payment_overdue, algorithm: :concurrently, if_not_exists: true
  end
end
