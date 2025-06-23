# frozen_string_literal: true

class CreateDataExports < ActiveRecord::Migration[7.0]
  def change
    create_table :data_exports, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.integer :format
      t.string :resource_type, null: false
      t.jsonb :resource_query, null: false, default: {}
      t.integer :status, null: false, default: 0
      t.timestamp :expires_at
      t.timestamp :started_at
      t.timestamp :completed_at

      t.timestamps
    end
  end
end
