# frozen_string_literal: true

class CreateWebhooks < ActiveRecord::Migration[7.0]
  def change
    create_table :webhooks, id: :uuid do |t|
      t.references :organization, index: true

      t.uuid :object_id, null: false
      t.string :object_type, null: false

      t.integer :status, default: 0, null: false
      t.integer :retries, default: 0, null: false
      t.integer :http_status

      t.string :endpoint
      t.string :webhook_type

      t.json :payload
      t.json :response

      t.timestamp :last_retried_at

      t.timestamps
    end
  end
end
