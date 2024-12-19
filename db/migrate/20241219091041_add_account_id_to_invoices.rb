class AddAccountIdToInvoices < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_reference :invoices, :account, type: :uuid, index: {algorithm: :concurrently}, if_not_exists: true

    safety_assured { execute "UPDATE invoices SET account_id = customer_id" }

    #change_column_null :invoices, :account_id, false
    add_index :invoices, %i[account_id sequential_id], unique: true, algorithm: :concurrently
  end

  def down
    remove_index :invoices, %i[account_id sequential_id], unique: true, algorithm: :concurrently
    remove_reference :invoices, :account, type: :uuid, index: {algorithm: :concurrently}
  end
end
