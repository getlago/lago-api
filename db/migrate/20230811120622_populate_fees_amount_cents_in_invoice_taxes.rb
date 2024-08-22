# frozen_string_literal: true

class PopulateFeesAmountCentsInInvoiceTaxes < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          WITH invoice_fees_amounts AS (
            SELECT
              invoices.id AS invoice_id,
              fees_taxes.tax_id,
              SUM(fees.amount_cents - fees.precise_coupons_amount_cents) AS fees_total_amount
            FROM fees
              INNER JOIN invoices ON invoices.id = fees.invoice_id
              INNER JOIN fees_taxes ON fees_taxes.fee_id = fees.id
            GROUP BY invoices.id, fees_taxes.tax_id
          )

          UPDATE invoices_taxes
          SET fees_amount_cents = invoice_fees_amounts.fees_total_amount
          FROM invoice_fees_amounts
            WHERE invoice_fees_amounts.invoice_id = invoices_taxes.invoice_id
            AND invoice_fees_amounts.tax_id = invoices_taxes.tax_id
          SQL
        end
      end
    end
  end
end
