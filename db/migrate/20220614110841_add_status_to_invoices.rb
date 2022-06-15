class AddStatusToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :status, :integer, null: false, default: 0
  end
end
