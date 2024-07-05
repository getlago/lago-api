# frozen_string_literal: true

class AddSignatureToWebhookEndpoints < ActiveRecord::Migration[7.0]
  def change
    add_column :webhook_endpoints, :signature_algo, :integer, default: 0, null: false # 0 is JWT
  end
end
