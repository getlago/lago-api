# frozen_string_literal: true

class AddIndicesToInboundWebhooks < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :inbound_webhooks,
      %i[status processing_at],
      where: "status = 'processing'",
      algorithm: :concurrently

    add_index :inbound_webhooks,
      %i[status created_at],
      where: "status = 'pending'",
      algorithm: :concurrently
  end
end
