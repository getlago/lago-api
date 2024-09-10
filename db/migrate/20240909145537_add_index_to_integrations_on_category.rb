class AddIndexToIntegrationsOnCategory < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :integrations, :category, algorithm: :concurrently
  end
end
