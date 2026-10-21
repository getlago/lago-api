# frozen_string_literal: true

class AddStandardWebhooksKeysToWebhookEndpoints < ActiveRecord::Migration[8.0]
  def change
    # private_key holds the ed25519 private key (`whsk_...`), encrypted at rest.
    # public_key holds the ed25519 public key (`whpk_...`), shared with consumers.
    add_column :webhook_endpoints, :private_key, :string, if_not_exists: true
    add_column :webhook_endpoints, :public_key, :string, if_not_exists: true
  end
end
