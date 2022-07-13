# frozen_string_literal: true

class ChangeActiveStorageAttachmentsIdType < ActiveRecord::Migration[7.0]
  def change
    remove_column :active_storage_attachments, :record_id
    add_column :active_storage_attachments, :record_id, :uuid
  end
end
