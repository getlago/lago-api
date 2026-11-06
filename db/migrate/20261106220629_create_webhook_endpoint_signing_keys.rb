# frozen_string_literal: true

class CreateWebhookEndpointSigningKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoint_signing_keys, id: :uuid, if_not_exists: true do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      # Not unique: a rotation keeps the previous key next to the new one.
      t.references :webhook_endpoint, type: :uuid, null: false, foreign_key: {on_delete: :cascade}, index: true
      t.text :secret, null: false
      t.timestamps
    end
  end
end
