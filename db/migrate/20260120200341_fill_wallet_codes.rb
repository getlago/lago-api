# frozen_string_literal: true

class FillWalletCodes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # Process wallets grouped by customer to handle uniqueness
    # Using a single UPDATE with CTEs is efficient for PostgreSQL
    # The CTE approach handles all rows in one query without loading into memory
    execute <<-SQL
      WITH base_codes AS (
        SELECT
          id,
          customer_id,
          created_at,
          CASE
            WHEN name IS NULL OR TRIM(name) = '' THEN 'default'
            ELSE LOWER(REGEXP_REPLACE(REGEXP_REPLACE(TRIM(name), '[^a-zA-Z0-9]+', '_', 'g'), '^_|_$', '', 'g'))
          END as base_code
        FROM wallets
        WHERE code IS NULL
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
        ELSE ranked_codes.base_code || '_' || TO_CHAR(ranked_codes.created_at, 'YYYYMMDDHH24MISS')
      END
      FROM ranked_codes
      WHERE wallets.id = ranked_codes.id
    SQL
  end

  def down
    execute "UPDATE wallets SET code = NULL"
  end
end
