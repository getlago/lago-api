# frozen_string_literal: true

class FillWalletCodes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 5_000

  def up
    # Process in batches by customer_id to:
    # 1. Reduce lock contention and transaction size
    # 2. Maintain uniqueness logic (all wallets for a customer processed together)
    safety_assured do
      loop do
        result = execute(<<-SQL)
          WITH customer_batch AS (
            SELECT DISTINCT customer_id
            FROM wallets
            WHERE code IS NULL
            LIMIT #{BATCH_SIZE}
          ),
          base_codes AS (
            SELECT
              w.id,
              w.customer_id,
              w.created_at,
              CASE
                WHEN w.name IS NULL OR TRIM(w.name) = '' THEN 'default'
                ELSE LOWER(REGEXP_REPLACE(REGEXP_REPLACE(TRIM(w.name), '[^a-zA-Z0-9]+', '_', 'g'), '^_|_$', '', 'g'))
              END as base_code
            FROM wallets w
            INNER JOIN customer_batch cb ON cb.customer_id = w.customer_id
            WHERE w.code IS NULL
          ),
          ranked_codes AS (
            SELECT
              id,
              customer_id,
              created_at,
              base_code,
              ROW_NUMBER() OVER (PARTITION BY customer_id, base_code ORDER BY created_at) as rn
            FROM base_codes
          )
          UPDATE wallets
          SET code = CASE
            WHEN ranked_codes.rn = 1 THEN ranked_codes.base_code
            ELSE ranked_codes.base_code || '_' || EXTRACT(EPOCH FROM ranked_codes.created_at)::bigint::text
          END
          FROM ranked_codes
          WHERE wallets.id = ranked_codes.id
        SQL

        break if result.cmd_tuples.zero?

        sleep(0.05) # Brief pause to reduce lock contention
      end
    end
  end

  def down
    # Also batch the rollback for large datasets
    safety_assured do
      loop do
        result = execute(<<-SQL)
          UPDATE wallets
          SET code = NULL
          WHERE id IN (
            SELECT id FROM wallets WHERE code IS NOT NULL LIMIT #{BATCH_SIZE}
          )
        SQL

        break if result.cmd_tuples.zero?
      end
    end
  end
end
