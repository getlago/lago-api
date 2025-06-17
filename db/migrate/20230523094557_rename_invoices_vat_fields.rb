# frozen_string_literal: true

class RenameInvoicesVatFields < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      rename_column :invoices, :vat_rate, :taxes_rate
      rename_column :invoices, :vat_amount_cents, :taxes_amount_cents
      rename_column :invoices, :sub_total_vat_excluded_amount_cents, :sub_total_excluding_taxes_amount_cents
      rename_column :invoices, :sub_total_vat_included_amount_cents, :sub_total_including_taxes_amount_cents
    end
  end
end
