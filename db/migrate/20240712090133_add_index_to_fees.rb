class AddIndexToFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :fees, [:charge_id, :invoice_id],
              name: 'index_fees_on_charge_id_and_invoice_id',
              where: 'deleted_at IS NULL'
  end
end
