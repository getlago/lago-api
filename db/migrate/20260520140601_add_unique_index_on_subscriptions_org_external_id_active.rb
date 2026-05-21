# frozen_string_literal: true

class AddUniqueIndexOnSubscriptionsOrgExternalIdActive < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    safety_assured do
      execute <<-SQL
        CREATE UNIQUE INDEX CONCURRENTLY index_subscriptions_on_org_external_id_active
        ON subscriptions (organization_id, external_id)
        WHERE (
          status = 1
          AND (
            created_at >= '2026-05-20 00:00:00'::timestamp without time zone
            OR activated_at >= '2026-05-20 00:00:00'::timestamp without time zone
          )
        )
      SQL
    end
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS index_subscriptions_on_org_external_id_active"
  end
end
