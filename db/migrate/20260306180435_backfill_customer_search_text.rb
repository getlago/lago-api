# frozen_string_literal: true

# The backfilling should be normally executed by the job & rake task (removed in this commit).
# The migration is kept here for those customers who haven't run the backfilling job for any reason
# to prevent breaking the search functionality.

class BackfillCustomerSearchText < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  BATCH_SIZE = 1_000

  def up
    safety_assured do
      loop do
        result = execute(<<-SQL)
          UPDATE customers
          SET search_text = CONCAT_WS(' ', name, firstname, lastname, external_id, email)
          WHERE id IN (
            SELECT id FROM customers
            WHERE search_text = '' OR search_text IS NULL
            LIMIT #{BATCH_SIZE}
          )
        SQL

        break if result.cmd_tuples.zero?
      end
    end
  end

  def down
    # No-op: the trigger keeps populating search_text on writes.
  end
end
