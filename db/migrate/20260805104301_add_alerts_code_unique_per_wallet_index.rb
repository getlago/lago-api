# frozen_string_literal: true

class AddAlertsCodeUniquePerWalletIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = "idx_alerts_code_unique_per_wallet"

  def up
    case index_state
    when :valid
      say "#{INDEX_NAME} is already in place, skipping the rename and the build"
      return
    when :invalid
      # A failed concurrent build leaves an invalid index still holding the name, which if_not_exists skips.
      say "Dropping #{INDEX_NAME} left invalid by an earlier failed build, so it can be rebuilt"
      remove_index :usage_monitoring_alerts, name: INDEX_NAME, algorithm: :concurrently
    end

    rename_codes_already_taken_on_the_same_wallet

    add_index :usage_monitoring_alerts, %i[code wallet_id organization_id],
      unique: true,
      where: "deleted_at IS NULL AND wallet_id IS NOT NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: INDEX_NAME
  end

  def down
    remove_index :usage_monitoring_alerts, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end

  private

  def index_state
    validity = select_value(<<~SQL.squish)
      SELECT i.indisvalid FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = '#{INDEX_NAME}'
    SQL

    if validity.nil?
      :missing
    elsif validity
      :valid
    else
      :invalid
    end
  end

  def rename_codes_already_taken_on_the_same_wallet
    # safety_assured: only touches rows the new index would reject.
    renamed = safety_assured { execute(<<~SQL) }
      WITH duplicates AS (
        SELECT a.id,
               a.code AS old_code,
               w.code AS wallet_code,
               row_number() OVER (
                 PARTITION BY a.organization_id, a.wallet_id, a.code
                 ORDER BY a.created_at, a.id
               ) AS position
        FROM usage_monitoring_alerts a
        JOIN wallets w ON w.id = a.wallet_id
        WHERE a.deleted_at IS NULL
      )
      UPDATE usage_monitoring_alerts a
      SET code = CASE
        WHEN NOT EXISTS (
          SELECT 1
          FROM usage_monitoring_alerts taken
          WHERE taken.organization_id = a.organization_id
            AND taken.wallet_id = a.wallet_id
            AND taken.deleted_at IS NULL
            AND taken.id <> a.id
            AND taken.code = a.code || '-' || a.alert_type::text
        ) THEN a.code || '-' || a.alert_type::text
        ELSE a.code || '-' || a.id::text
      END
      FROM duplicates d
      WHERE d.id = a.id AND d.position > 1
      RETURNING a.wallet_id, d.wallet_code, d.old_code, a.code AS new_code
    SQL

    return if renamed.ntuples.zero?

    say "Renamed #{renamed.ntuples} wallet alert(s) whose code was already used on the same wallet."

    renamed.sort_by { [it["wallet_id"], it["old_code"]] }.each do |row|
      wallet = row["wallet_code"].present? ? "#{row["wallet_id"]} (#{row["wallet_code"]})" : row["wallet_id"]
      say "wallet #{wallet}: #{row["old_code"]} -> #{row["new_code"]}", true
    end
  end
end
