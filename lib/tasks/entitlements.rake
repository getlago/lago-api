# frozen_string_literal: true

namespace :entitlements do
  desc "Soft-delete duplicate subscription entitlements that have no values and whose feature is already on the parent plan"
  task :cleanup_duplicate_subscription_entitlements, [:organization_id] => :environment do |_task, args|
    organization_id = args[:organization_id]
    abort "Missing organization_id argument\n\nUsage: rake entitlements:cleanup_duplicate_subscription_entitlements[organization_id]" unless organization_id

    deleted_at = Time.current.beginning_of_hour
    read_batch_size = 100_000
    write_batch_size = 10_000
    total_deleted = 0

    find_duplicates_sql = <<~SQL.squish
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
        AND sub_ent.organization_id = $1
        AND NOT EXISTS (
          SELECT 1 FROM entitlement_entitlement_values v
          WHERE v.entitlement_entitlement_id = sub_ent.id
            AND v.deleted_at IS NULL
        )
    SQL

    total_matching = ActiveRecord::Base.connection.select_value(
      "SELECT COUNT(*) FROM (#{find_duplicates_sql}) AS duplicates", "Count duplicate entitlements", [organization_id]
    )

    puts "Starting cleanup of duplicate subscription entitlements for organization #{organization_id} (deleted_at: #{deleted_at})..."
    puts "Found #{total_matching} matching entitlements to soft-delete."

    loop do
      matching_ids = ActiveRecord::Base.connection.select_values(
        "#{find_duplicates_sql} LIMIT $2", "Find duplicate entitlements", [organization_id, read_batch_size]
      )

      break if matching_ids.empty?

      matching_ids.each_slice(write_batch_size) do |ids|
        result = ActiveRecord::Base.connection.exec_update(<<~SQL.squish, "Cleanup duplicate entitlements", [deleted_at, "{#{ids.join(",")}}"])
          UPDATE entitlement_entitlements
          SET deleted_at = $1
          WHERE id = ANY($2)
        SQL

        total_deleted += result
        puts "  Progress: #{total_deleted}/#{total_matching} entitlements deleted..."
      end
    end

    puts "Done. Soft-deleted #{total_deleted} entitlements."
  end
end
