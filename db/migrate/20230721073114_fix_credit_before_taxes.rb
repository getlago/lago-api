# frozen_string_literal: true

class FixCreditBeforeTaxes < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        safety_assured do
          execute <<-SQL
          WITH wrong_before_vat_credits AS (
            SELECT credits.id AS credit_id
            FROM credits
            INNER JOIN invoices ON credits.invoice_id = invoices.id
            WHERE invoices.version_number = 3
              AND credits.before_taxes IS false
              AND credits.applied_coupon_id IS NOT NULL
          )

          UPDATE credits
          SET before_taxes = true
          FROM wrong_before_vat_credits
            WHERE wrong_before_vat_credits.credit_id = credits.id;
          SQL
        end
      end
    end
  end
end
