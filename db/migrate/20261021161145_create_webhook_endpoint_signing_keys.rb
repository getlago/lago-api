# frozen_string_literal: true

class CreateWebhookEndpointSigningKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_endpoint_signing_keys, id: :uuid, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid, index: true
      t.references :webhook_endpoint, null: false, foreign_key: true, type: :uuid, index: true

      # Standard Webhooks `v1` secret (`whsec_...`), encrypted at rest.
      t.string :secret, null: false

      # When set, the key is being rotated out and stops signing once passed.
      t.datetime :expires_at, index: true

      t.timestamps
    end
  end
end
