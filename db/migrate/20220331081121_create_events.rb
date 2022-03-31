# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :events, id: :uuid do |t|
      t.references :organization, type: :uuid, index: true, null: false, foreign_key: true
      t.references :customer, type: :uuid, foreign_key: true, index: true, null: false

      t.string :transaction_id, null: false
      t.string :code, null: false
      t.jsonb :properties, null: false, default: {}
      t.timestamp :timestamp

      t.index [:organization_id, :code]
      t.index [:organization_id, :transaction_id], unique: true

      t.timestamps
    end
  end
end
