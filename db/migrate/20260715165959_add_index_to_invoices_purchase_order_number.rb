# frozen_string_literal: true

class AddIndexToInvoicesPurchaseOrderNumber < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :invoices, :purchase_order_number,
      algorithm: :concurrently,
      using: :btree,
      if_not_exists: true
  end
end
