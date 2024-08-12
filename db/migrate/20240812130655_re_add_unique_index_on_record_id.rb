# frozen_string_literal: true

class ReAddUniqueIndexOnRecordId < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :active_storage_attachments, [:record_type, :record_id, :name, :blob_id],
      name: :index_active_storage_attachments_uniqueness,
      unique: true,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :active_storage_attachments, name: 'index_active_storage_attachments_uniqueness', algorithm: :concurrently
  end
end
