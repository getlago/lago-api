# frozen_string_literal: true

class PopulateDuplicatedInAdvanceFees < ActiveRecord::Migration[8.0]
  def up
    query = <<~SQL
      WITH duplicated_fees AS (
        SELECT organization_id, pay_in_advance_event_transaction_id, charge_id, charge_filter_id
        FROM fees
        WHERE fees.deleted_at IS NULL
          AND fees.pay_in_advance = TRUE
          AND fees.pay_in_advance_event_transaction_id IS NOT NULL
          AND (created_at > '2025-01-21 00:00:00')  -- TODO: check what happened before...
        GROUP BY pay_in_advance_event_transaction_id, charge_id, charge_filter_id, organization_id
        HAVING COUNT(*) > 1
      )
      UPDATE fees f
      SET duplicated_in_advance = TRUE
      FROM duplicated_fees df
      WHERE f.pay_in_advance_event_transaction_id = df.pay_in_advance_event_transaction_id
        AND f.charge_id = df.charge_id
        AND f.charge_filter_id = df.charge_filter_id
        AND f.organization_id = df.organization_id
        AND f.pay_in_advance = TRUE
        AND f.deleted_at IS NULL;
    SQL

    safety_assured { execute(query) }
  end
end
