# frozen_string_literal: true

class CreateIntegrationErrorDetails < ActiveRecord::Migration[7.1]
  def change
    create_table :error_details, id: :uuid do |t|
      t.references :owner, type: :uuid, polymorphic: true, null: false, index: true
      t.references :integration, type: :uuid, polymorphic: true, index: true, null: true
      t.references :organization, type: :uuid, index: true, foreign_key: true, null: false
      t.string :error_code, index: true, null: false, default: 'not_provided'
      t.jsonb :details, null: false, default: {}
      t.datetime :deleted_at, index: true

      t.timestamps
    end
  end
end
