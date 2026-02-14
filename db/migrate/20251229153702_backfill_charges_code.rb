# frozen_string_literal: true

class BackfillChargesCode < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 5_000

  def up
    # Backfill charges code based on billable_metric code.
    # Compute all codes upfront in a temp table to ensure correct sequencing,
    # then batch the updates to avoid locking.
    safety_assured do
      execute <<~SQL.squish
        CREATE TEMPORARY TABLE tmp_charges_code AS
        SELECT
          c.id,
          CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY c.plan_id, bm.code ORDER BY c.created_at, c.id) = 1
            THEN bm.code
            ELSE bm.code || '_' || ROW_NUMBER() OVER (PARTITION BY c.plan_id, bm.code ORDER BY c.created_at, c.id)
          END AS new_code
        FROM charges c
        JOIN billable_metrics bm ON bm.id = c.billable_metric_id
        WHERE c.code IS NULL
      SQL
    end

    loop do
      rows_affected = exec_update(<<~SQL.squish)
        WITH batch AS (
          DELETE FROM tmp_charges_code
          WHERE id IN (SELECT id FROM tmp_charges_code LIMIT #{BATCH_SIZE})
          RETURNING id, new_code
        )
        UPDATE charges
        SET code = batch.new_code
        FROM batch
        WHERE charges.id = batch.id
      SQL

      break if rows_affected < BATCH_SIZE
    end

    execute "DROP TABLE IF EXISTS tmp_charges_code"

    # Backfill fixed_charges code based on add_on code
    safety_assured do
      execute <<~SQL.squish
        CREATE TEMPORARY TABLE tmp_fixed_charges_code AS
        SELECT
          fc.id,
          CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY fc.plan_id, ao.code ORDER BY fc.created_at, fc.id) = 1
            THEN ao.code
            ELSE ao.code || '_' || ROW_NUMBER() OVER (PARTITION BY fc.plan_id, ao.code ORDER BY fc.created_at, fc.id)
          END AS new_code
        FROM fixed_charges fc
        JOIN add_ons ao ON ao.id = fc.add_on_id
        WHERE fc.code IS NULL
      SQL
    end

    loop do
      rows_affected = exec_update(<<~SQL.squish)
        WITH batch AS (
          DELETE FROM tmp_fixed_charges_code
          WHERE id IN (SELECT id FROM tmp_fixed_charges_code LIMIT #{BATCH_SIZE})
          RETURNING id, new_code
        )
        UPDATE fixed_charges
        SET code = batch.new_code
        FROM batch
        WHERE fixed_charges.id = batch.id
      SQL

      break if rows_affected < BATCH_SIZE
    end

    execute "DROP TABLE IF EXISTS tmp_fixed_charges_code"
  end

  def down
    loop do
      rows_affected = exec_update(<<~SQL.squish)
        UPDATE charges SET code = NULL WHERE id IN (
          SELECT id FROM charges WHERE code IS NOT NULL LIMIT #{BATCH_SIZE}
        )
      SQL

      break if rows_affected < BATCH_SIZE
    end

    loop do
      rows_affected = exec_update(<<~SQL.squish)
        UPDATE fixed_charges SET code = NULL WHERE id IN (
          SELECT id FROM fixed_charges WHERE code IS NOT NULL LIMIT #{BATCH_SIZE}
        )
      SQL

      break if rows_affected < BATCH_SIZE
    end
  end
end
