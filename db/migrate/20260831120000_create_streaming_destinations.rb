# frozen_string_literal: true

class CreateStreamingDestinations < ActiveRecord::Migration[8.0]
  def change
    create_table :streaming_destinations, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid

      t.string :type, null: false
      t.string :code, null: false
      t.string :name, null: false

      # null subscribes the destination to every webhook event type.
      t.string :event_types, array: true

      t.jsonb :settings, null: false, default: {}
      t.string :secrets

      t.datetime :deleted_at

      t.timestamps

      # Partial, so a discarded destination frees its code for reuse. It cannot
      # stand in for the organization_id index above, which stays for lookups
      # that must also see discarded rows.
      t.index [:organization_id, :code],
        unique: true,
        where: "deleted_at IS NULL",
        name: "index_unique_streaming_destinations_on_organization_code"
      t.index :deleted_at
    end
  end
end
