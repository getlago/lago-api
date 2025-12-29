# frozen_string_literal: true

class BackfillChargesCode < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      # Backfill charges code based on billable_metric code
      execute <<~SQL.squish
        WITH ranked_charges AS (
          SELECT
            c.id,
            bm.code AS billable_metric_code,
            ROW_NUMBER() OVER (
              PARTITION BY c.plan_id, bm.code
              ORDER BY c.created_at, c.id
            ) AS seq_num
          FROM charges c
          JOIN billable_metrics bm ON bm.id = c.billable_metric_id
          WHERE c.code IS NULL
        )
        UPDATE charges
        SET code = CASE
          WHEN ranked_charges.seq_num = 1
          THEN ranked_charges.billable_metric_code
          ELSE ranked_charges.billable_metric_code || '_' || ranked_charges.seq_num
        END
        FROM ranked_charges
        WHERE charges.id = ranked_charges.id
      SQL

      # Backfill fixed_charges code based on add_on code
      execute <<~SQL.squish
        WITH ranked_fixed_charges AS (
          SELECT
            fc.id,
            ao.code AS add_on_code,
            ROW_NUMBER() OVER (
              PARTITION BY fc.plan_id, ao.code
              ORDER BY fc.created_at, fc.id
            ) AS seq_num
          FROM fixed_charges fc
          JOIN add_ons ao ON ao.id = fc.add_on_id
          WHERE fc.code IS NULL
        )
        UPDATE fixed_charges
        SET code = CASE
          WHEN ranked_fixed_charges.seq_num = 1
          THEN ranked_fixed_charges.add_on_code
          ELSE ranked_fixed_charges.add_on_code || '_' || ranked_fixed_charges.seq_num
        END
        FROM ranked_fixed_charges
        WHERE fixed_charges.id = ranked_fixed_charges.id
      SQL
    end
  end

  def down
    safety_assured do
      execute <<~SQL.squish
        UPDATE charges SET code = NULL
      SQL

      execute <<~SQL.squish
        UPDATE fixed_charges SET code = NULL
      SQL
    end
  end
end
