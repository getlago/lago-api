# frozen_string_literal: true

class AddUniqueIndexToWebhookUrls < ActiveRecord::Migration[7.0]
  def change
    add_index :webhook_endpoints, [:webhook_url, :organization_id], unique: true
  end
end
