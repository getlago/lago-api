# frozen_string_literal: true

class AddIndexOnWebhooksEndpointTypeUpdated < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :webhooks,
      [:webhook_endpoint_id, :webhook_type, :updated_at],
      order: {updated_at: :desc},
      name: :idx_webhooks_on_endpoint_id_type_updated_at,
      algorithm: :concurrently
  end
end
