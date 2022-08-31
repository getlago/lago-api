class RenameUniqueIdToExternalIdOnSubscriptions < ActiveRecord::Migration[7.0]
  def change
    rename_column :subscriptions, :unique_id, :external_id
    add_index :subscriptions, :external_id
  end
end
