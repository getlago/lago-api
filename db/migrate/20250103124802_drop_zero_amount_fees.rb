# frozen_string_literal: true

class DropZeroAmountFees < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    sql = <<~SQL
      DELETE FROM fees
      USING invoices
      WHERE
        fees.invoice_id = invoices.id
        AND invoices.status IN (1, 2, 6) -- finalized, voided and closed
        AND fees.fee_type = 0 -- charge
        AND fees.amount_cents = 0
        AND fees.units = 0
        AND fees.pay_in_advance = false
        AND fees.true_up_parent_fee_id IS NULL
        AND fees.id NOT IN (
          SELECT f.true_up_parent_fee_id
          FROM fees f
          WHERE f.true_up_parent_fee_id IS NOT NULL
        )
        AND fees.id NOT IN (
          SELECT fee_id
          FROM adjusted_fees
          WHERE adjusted_fees.fee_id IS NOT NULL
        )
    SQL

    ApplicationRecord.connection.execute(sql)
  end
end
