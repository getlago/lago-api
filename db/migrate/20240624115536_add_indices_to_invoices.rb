class AddIndicesToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_index :invoices, :currency
    add_index :invoices, :issuing_date
    add_index :invoices, :invoice_type
    add_index :invoices, :status
    add_index :invoices, :payment_status
    add_index :invoices, :payment_dispute_lost_at
  end
end
