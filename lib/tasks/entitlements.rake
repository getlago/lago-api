# frozen_string_literal: true

namespace :entitlements do
  desc "Soft-delete duplicate subscription entitlements that have no values and whose feature is already on the parent plan"
  task :cleanup_duplicate_subscription_entitlements, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id]
    abort "Missing organization_id argument\n\nUsage: rake entitlements:cleanup_duplicate_subscription_entitlements[organization_id]" unless organization_id

    deleted_at = Time.current.beginning_of_hour
    batch_size = 5_000
    total_deleted = 0
    total_pages = 0
    cache_key_prefix = "entitlements_cleanup:#{organization_id}"
    conn = ActiveRecord::Base.connection

    puts "Starting cleanup of duplicate subscription entitlements for organization #{organization_id} (deleted_at: #{deleted_at})..."

    begin
      # Phase 1: Collect all candidate IDs using keyset pagination and store in Redis.
      # The expensive joins + NOT EXISTS run once here, not repeated per batch.
      puts "Collecting candidate IDs..."
      last_id = "00000000-0000-0000-0000-000000000000"
      total_to_delete = 0

      loop do
        sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, organization_id, last_id, batch_size])
          SELECT sub_ent.id
          FROM entitlement_entitlements sub_ent
          JOIN subscriptions s ON s.id = sub_ent.subscription_id
          JOIN plans p ON p.id = s.plan_id
          JOIN entitlement_entitlements plan_ent
            ON plan_ent.entitlement_feature_id = sub_ent.entitlement_feature_id
            AND plan_ent.plan_id = COALESCE(p.parent_id, p.id)
            AND plan_ent.deleted_at IS NULL
          WHERE sub_ent.subscription_id IS NOT NULL
            AND sub_ent.deleted_at IS NULL
            AND sub_ent.organization_id = ?
            AND sub_ent.id > ?
            AND NOT EXISTS (
              SELECT 1 FROM entitlement_entitlement_values v
              WHERE v.entitlement_entitlement_id = sub_ent.id
                AND v.deleted_at IS NULL
            )
          ORDER BY sub_ent.id
          LIMIT ?
        SQL

        ids = conn.select_values(sql, "Fetch candidate IDs (page #{total_pages})")
        break if ids.empty?

        # ~180KB per batch (5000 UUIDs x 36 bytes)
        Rails.cache.write("#{cache_key_prefix}:#{total_pages}", ids, expires_in: 1.hour)
        total_to_delete += ids.size
        last_id = ids.last
        total_pages += 1

        break if ids.size < batch_size
      end

      puts "Found #{total_to_delete} entitlements to soft-delete (#{total_pages} batches)."

      # Phase 2: Process each batch from Redis with a simple UPDATE (no joins).
      total_pages.times do |index|
        ids = Rails.cache.read("#{cache_key_prefix}:#{index}")
        next if ids.blank?

        update_sql = ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, deleted_at, ids])
          UPDATE entitlement_entitlements
          SET deleted_at = ?
          WHERE id IN (?)
        SQL

        conn.exec_update(update_sql, "Batch soft-delete entitlements (#{index + 1}/#{total_pages})")

        total_deleted += ids.size
        Rails.cache.delete("#{cache_key_prefix}:#{index}")
        puts "  Progress: #{total_deleted}/#{total_to_delete} entitlements deleted..." if (total_deleted % 25_000) < batch_size
      end
    ensure
      total_pages.times { |index| Rails.cache.delete("#{cache_key_prefix}:#{index}") }
    end

    puts "Done. Soft-deleted #{total_deleted} entitlements."
  end
end
