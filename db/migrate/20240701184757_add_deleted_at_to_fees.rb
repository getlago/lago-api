class AddDeletedAtToFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :fees, :deleted_at, :datetime
    add_index :fees, :deleted_at, algorithm: :concurrently
  end
end