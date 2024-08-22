# frozen_string_literal: true

class AddUniqueIndexToAppliedTaxes < ActiveRecord::Migration[7.0]
  def change
    safety_assured do
      add_index :add_ons_taxes, %i[add_on_id tax_id], unique: true
      add_index :charges_taxes, %i[charge_id tax_id], unique: true
      add_index :credit_notes_taxes, %i[credit_note_id tax_id], unique: true
      add_index :customers_taxes, %i[customer_id tax_id], unique: true
      add_index :plans_taxes, %i[plan_id tax_id], unique: true

      add_index :fees_taxes,
        %i[fee_id tax_id],
        unique: true,
        where: "created_at >= '2023-09-12'"

      add_index :invoices_taxes,
        %i[invoice_id tax_id],
        unique: true,
        where: "created_at >= '2023-09-12'"
    end
  end
end
