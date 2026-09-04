# frozen_string_literal: true

class CreateRecordDeletions < ActiveRecord::Migration[8.0]
  def change
    create_table :record_deletions, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: false

      t.string :record_table, null: false
      t.uuid :record_id, null: false

      # Defaulted in the database: the record_deletion() trigger inserts outside ActiveRecord.
      t.datetime :deleted_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps default: -> { "CURRENT_TIMESTAMP" }

      t.index %i[organization_id deleted_at], name: "idx_lookup_on_record_deletions"
      t.index :deleted_at, name: "idx_retention_on_record_deletions"
      t.index :updated_at, name: "idx_sync_cursor_on_record_deletions"
    end
  end
end
