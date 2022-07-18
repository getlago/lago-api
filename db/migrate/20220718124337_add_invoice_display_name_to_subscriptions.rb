class AddInvoiceDisplayNameToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :invoice_display_name, :string
  end
end
