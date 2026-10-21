# frozen_string_literal: true

class CreateWebhookEndpointSigningKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_endpoint_signing_keys, id: :uuid, if_not_exists: true do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid, index: true
      t.references :webhook_endpoint, null: false, foreign_key: true, type: :uuid, index: true

      # ed25519 key pair for Standard Webhooks `v1a` signatures.
      # private_key (`whsk_...`) is encrypted at rest, public_key (`whpk_...`) is shared.
      t.string :private_key, null: false
      t.string :public_key, null: false

      # When set, the key is being rotated out and stops signing once passed.
      t.datetime :expires_at

      t.timestamps
    end

    add_index :webhook_endpoint_signing_keys, :expires_at, if_not_exists: true
  end
end
