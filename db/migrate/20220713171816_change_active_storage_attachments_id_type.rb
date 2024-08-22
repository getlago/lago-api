# frozen_string_literal: true

class ChangeActiveStorageAttachmentsIdType < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :active_storage_attachments, bulk: true do |t|
        t.remove :record_id # rubocop:disable Rails/ReversibleMigration
        t.uuid :record_id
      end
    end
  end
end
