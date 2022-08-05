class RemoveInvoiceColumns < ActiveRecord::Migration[7.0]
  def change
    remove_column :invoices, :from_date
    remove_column :invoices, :to_date
    remove_column :invoices, :charges_from_date
  end
end
