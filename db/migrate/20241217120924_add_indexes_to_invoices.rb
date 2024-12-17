# frozen_string_literal: true

class AddIndexesToInvoices < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :invoices, :ready_to_be_refreshed, where: "ready_to_be_refreshed", algorithm: :concurrently
    add_index :invoices, :issuing_date, algorithm: :concurrently
  end
end
