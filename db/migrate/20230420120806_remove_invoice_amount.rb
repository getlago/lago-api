# frozen_string_literal: true

class RemoveInvoiceAmount < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      remove_column :invoices, :amount_cents
    end
  end

  def down
    add_column :invoices, :amount_cents, :bigint, default: 0

    execute <<-SQL
      WITH fee_amount AS (
        SELECT fees.invoice_id,
          SUM(fees.amount_cents) AS amount_cents
        FROM fees
        GROUP BY fees.invoice_id
      )
      UPDATE invoices
      SET amount_cents = fee_amount.amount_cents
      FROM fee_amount
      WHERE invoices.id = fee_amount.invoice_id
    SQL
  end
end
