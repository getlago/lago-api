# frozen_string_literal: true

class AddInvoiceTypeToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :invoice_type, :integer, null: false, default: 0
  end
end
