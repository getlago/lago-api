class DropInvoiceErrorTable < ActiveRecord::Migration[7.1]
  def change
    drop_table :invoice_errors
  end
end
