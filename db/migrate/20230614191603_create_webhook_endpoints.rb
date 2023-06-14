# frozen_string_literal: true

class CreateWebhookEndpoints < ActiveRecord::Migration[7.0]
  def up
    create_table :webhook_endpoints, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, index: true, type: :uuid
      t.string :webhook_url, null: false

      t.timestamps
    end

    add_reference :webhooks, :webhook_endpoint, type: :uuid, foreign_key: true, index: true

    Organization.find_each do |organization|
      webhook_endpoint = WebhookEndpoint
        .where(organization:, webhook_url: organization.webhook_url).first_or_create!

      Webhook.where(organization_id: organization.id).find_each do |webhook|
        webhook.update!(webhook_endpoint:)
      end
    end
  end

  def down
    remove_reference :webhooks, :webhook_endpoint, index: true
    drop_table :webhook_endpoints
  end
end
