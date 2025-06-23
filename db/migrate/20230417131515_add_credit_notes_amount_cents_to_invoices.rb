# frozen_string_literal: true

class AddCreditNotesAmountCentsToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :credit_notes_amount_cents, :bigint, null: false, default: 0

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          WITH credit_notes_total AS (
            SELECT credits.invoice_id, sum(credits.amount_cents) AS credit_notes_amount_cents
            FROM credits
            WHERE credit_note_id IS NOT NULL
            GROUP BY credits.invoice_id
          )
          UPDATE invoices
          SET credit_notes_amount_cents = credit_notes_total.credit_notes_amount_cents
          FROM credit_notes_total
          WHERE invoices.id = credit_notes_total.invoice_id
          SQL
        end
      end
    end
  end
end
