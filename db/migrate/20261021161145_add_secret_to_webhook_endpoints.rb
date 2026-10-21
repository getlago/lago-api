# frozen_string_literal: true

class AddSecretToWebhookEndpoints < ActiveRecord::Migration[8.0]
  def change
    add_column :webhook_endpoints, :secret, :string, if_not_exists: true
  end
end
