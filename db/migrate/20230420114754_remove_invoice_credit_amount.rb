# frozen_string_literal: true

class RemoveInvoiceCreditAmount < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      remove_column :invoices, :credit_amount_cents
    end
  end

  def down
    add_column :invoices, :credit_amount_cents, :bigint, null: false, default: 0

    reversible do |dir|
      dir.up do
        execute <<-SQL
          WITH credit_amount AS (
            SELECT credits.invoice_id,
              SUM(credits.amount_cents) AS amount_cents
            FROM credits
            GROUP BY credits.invoice_id
          )
          UPDATE invoices
          SET credit_amount_cents = credit_amount.amount_cents + prepaid_credit_amount_cents
          FROM credit_amount
          WHERE invoices.id = credit_amount.invoice_id
        SQL
      end
    end
  end
end
