# frozen_string_literal: true

class CreateStreamingDestinations < ActiveRecord::Migration[8.0]
  def change
    create_table :streaming_destinations, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.string :type, null: false

      t.string :event_types, array: true, null: false, default: []

      t.jsonb :settings, null: false, default: {}
      t.string :secrets

      t.timestamps

      t.index :event_types, using: :gin
    end
  end
end
