# frozen_string_literal: true

class AddProcessingAtToInboundWebhooks < ActiveRecord::Migration[7.1]
  def change
    add_column :inbound_webhooks, :processing_at, :timestamp, precision: nil
  end
end
