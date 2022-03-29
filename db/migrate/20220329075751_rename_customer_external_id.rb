class RenameCustomerExternalId < ActiveRecord::Migration[7.0]
  def change
    rename_column :customers, :external_id, :customer_id
  end
end
