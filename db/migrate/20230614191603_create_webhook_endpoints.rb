# frozen_string_literal: true

class CreateWebhookEndpoints < ActiveRecord::Migration[7.0]
  def up
    create_table :webhook_endpoints, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, index: true, type: :uuid
      t.string :webhook_url, null: false

      t.timestamps
    end

    safety_assured do
      add_reference :webhooks, :webhook_endpoint, type: :uuid, foreign_key: true, index: true

      execute(<<~SQL.squish)
        insert into webhook_endpoints(organization_id, webhook_url, created_at, updated_at)
        select id, webhook_url, NOW(), NOW() from organizations where (webhook_url is not null or webhook_url <> '');
      SQL

      execute(<<~SQL.squish)
        update webhooks
        set webhook_endpoint_id = whe.id
        from (select id, organization_id from webhook_endpoints) as whe
        where webhooks.organization_id = whe.organization_id;
      SQL

      remove_reference :webhooks, :organization, index: true
    end
  end

  def down
    remove_reference :webhooks, :webhook_endpoint, index: true
    drop_table :webhook_endpoints

    add_reference :webhooks, :organization, type: :uuid, index: true, null: false # rubocop:disable Rails/NotNullColumn
  end
end
