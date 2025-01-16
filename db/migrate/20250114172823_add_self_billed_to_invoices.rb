# frozen_string_literal: true

class AddSelfBilledToInvoices < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :invoices, :self_billed, :boolean, default: false, null: false
    add_index :invoices, :self_billed, algorithm: :concurrently
  end
end
