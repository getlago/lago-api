# frozen_string_literal: true

class AddAlertsCodeUniquePerWalletIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = "idx_alerts_code_unique_per_wallet"

  def up
    rename_codes_already_taken_on_the_same_wallet

    # A failed concurrent build leaves an invalid index that IF NOT EXISTS skips: check indisvalid before retrying.
    add_index :usage_monitoring_alerts, %i[code wallet_id organization_id],
      unique: true,
      where: "deleted_at IS NULL",
      algorithm: :concurrently,
      if_not_exists: true,
      name: INDEX_NAME
  end

  def down
    remove_index :usage_monitoring_alerts, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end

  private

  # The type suffix cannot collide, because one alert type per wallet is already unique.
  def rename_codes_already_taken_on_the_same_wallet
    # safety_assured: strong_migrations cannot inspect an execute. This one only touches rows the new index rejects.
    renamed = safety_assured { execute(<<~SQL) }
      WITH candidates AS (
        SELECT wallet_id, organization_id
        FROM usage_monitoring_alerts
        WHERE deleted_at IS NULL
          AND billable_metric_id IS NULL
          AND wallet_id IS NOT NULL
        GROUP BY wallet_id, organization_id
        HAVING count(*) > 1
      ), duplicates AS (
        SELECT a.id,
               a.code AS old_code,
               w.code AS wallet_code,
               row_number() OVER (
                 PARTITION BY a.organization_id, a.wallet_id, a.code
                 ORDER BY a.created_at, a.id
               ) AS position
        FROM usage_monitoring_alerts a
        JOIN candidates c
          ON c.wallet_id = a.wallet_id AND c.organization_id = a.organization_id
        JOIN wallets w ON w.id = a.wallet_id
        WHERE a.deleted_at IS NULL
      )
      UPDATE usage_monitoring_alerts a
      SET code = a.code || '-' || a.alert_type::text
      FROM duplicates d
      WHERE d.id = a.id AND d.position > 1
      RETURNING a.wallet_id, d.wallet_code, d.old_code, a.code AS new_code
    SQL

    if renamed.ntuples > 0
      say "Renamed #{renamed.ntuples} wallet alert(s) whose code was already used on the same wallet, suffixing the alert type."

      renamed.sort_by { [it["wallet_id"], it["old_code"]] }.each do |row|
        wallet = row["wallet_code"].present? ? "#{row["wallet_id"]} (#{row["wallet_code"]})" : row["wallet_id"]
        say "wallet #{wallet}: #{row["old_code"]} -> #{row["new_code"]}", true
      end
    end
  end
end
