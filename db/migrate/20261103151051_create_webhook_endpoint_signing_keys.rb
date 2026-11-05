# frozen_string_literal: true

class CreateWebhookEndpointSigningKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_endpoint_signing_keys, id: :uuid, if_not_exists: true do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.references :webhook_endpoint, type: :uuid, null: false, foreign_key: true, index: true
      t.string :secret_key, null: false
      t.datetime :expires_at
      t.timestamps
    end
  end
end
