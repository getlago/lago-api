class RenameCustomerIdToExternalIdOnCustomers < ActiveRecord::Migration[7.0]
  def change
    rename_column :customers, :customer_id, :external_id
  end
end
