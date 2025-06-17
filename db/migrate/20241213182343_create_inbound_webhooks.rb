# frozen_string_literal: true

class CreateInboundWebhooks < ActiveRecord::Migration[7.1]
  def change
    create_enum :inbound_webhook_status, %w[pending processing succeeded failed]

    create_table :inbound_webhooks, id: :uuid do |t|
      t.string :source, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false
      t.enum :status, enum_type: "inbound_webhook_status", null: false, default: "pending"
      t.belongs_to :organization, null: false, foreign_key: true, type: :uuid, index: true
      t.string :code
      t.string :signature

      t.timestamps
    end
  end
end
