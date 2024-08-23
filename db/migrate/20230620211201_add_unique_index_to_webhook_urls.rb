# frozen_string_literal: true

class AddUniqueIndexToWebhookUrls < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_index :webhook_endpoints, [:webhook_url, :organization_id], unique: true
    end
  end
end
