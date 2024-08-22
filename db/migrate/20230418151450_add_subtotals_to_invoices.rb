# frozen_string_literal: true

class AddSubtotalsToInvoices < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      change_table :invoices, bulk: true do |t|
        t.bigint :sub_total_vat_excluded_amount_cents, null: false, default: 0
        t.bigint :sub_total_vat_included_amount_cents, null: false, default: 0
      end

      reversible do |dir|
        dir.up do
          execute <<-SQL
          UPDATE invoices
          SET sub_total_vat_excluded_amount_cents = amount_cents + prepaid_credit_amount_cents,
            sub_total_vat_included_amount_cents = total_amount_cents
          WHERE version_number = 1
          SQL

          execute <<-SQL
          UPDATE invoices
          SET sub_total_vat_excluded_amount_cents = fees_amount_cents,
            sub_total_vat_included_amount_cents = fees_amount_cents + vat_amount_cents
          WHERE version_number = 2
          SQL
        end
      end
    end
  end
end
