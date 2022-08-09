class AddCustomerToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_reference :invoices, :customer, type: :uuid, foreign_key: true, index: true
  end
end
