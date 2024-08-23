# frozen_String_literal: true

class AddFeesAmountCentsToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :fees_amount_cents, :bigint, null: false, default: 0
    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          WITH fees_total AS (
            SELECT fees.invoice_id, sum(fees.amount_cents) AS fees_amount_cents
            FROM fees
            GROUP BY fees.invoice_id
          )
          UPDATE invoices
          SET fees_amount_cents = fees_total.fees_amount_cents
          FROM fees_total
          WHERE invoices.id = fees_total.invoice_id
          SQL
        end
      end
    end
  end
end
