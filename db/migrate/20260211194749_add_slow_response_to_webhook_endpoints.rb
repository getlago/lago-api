# frozen_string_literal: true

class AddSlowResponseToWebhookEndpoints < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_column :webhook_endpoints, :slow_response, :boolean, default: false, null: false
    add_index :webhook_endpoints, :slow_response, algorithm: :concurrently
  end
end
