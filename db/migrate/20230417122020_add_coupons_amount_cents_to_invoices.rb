# frozen_string_literal: true

class AddCouponsAmountCentsToInvoices < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :coupons_amount_cents, :bigint, null: false, default: 0

    safety_assured do
      reversible do |dir|
        dir.up do
          execute <<-SQL
          WITH coupons_total AS (
            SELECT credits.invoice_id, sum(credits.amount_cents) AS coupons_amount_cents
            FROM credits
            WHERE applied_coupon_id IS NOT NULL
            GROUP BY credits.invoice_id
          )
          UPDATE invoices
          SET coupons_amount_cents = coupons_total.coupons_amount_cents
          FROM coupons_total
          WHERE invoices.id = coupons_total.invoice_id
          SQL
        end
      end
    end
  end
end
