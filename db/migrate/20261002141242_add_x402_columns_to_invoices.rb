# frozen_string_literal: true

class AddX402ColumnsToInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :invoices, :x402_payment_token, :string, if_not_exists: true
    add_column :invoices, :x402_connection_id, :uuid, if_not_exists: true
  end
end
