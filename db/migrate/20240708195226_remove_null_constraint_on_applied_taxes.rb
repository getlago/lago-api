# frozen_string_literal: true

class RemoveNullConstraintOnAppliedTaxes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    change_column_null :fees_taxes, :tax_id, true
    change_column_null :invoices_taxes, :tax_id, true

    remove_index :fees_taxes, %i[fee_id tax_id]
    remove_index :invoices_taxes, %i[invoice_id tax_id]

    add_index :fees_taxes,
      %i[fee_id tax_id],
      unique: true,
      where: "tax_id IS NOT NULL AND created_at >= '2023-09-12'",
      algorithm: :concurrently

    add_index :invoices_taxes,
      %i[invoice_id tax_id],
      unique: true,
      where: "tax_id IS NOT NULL AND created_at >= '2023-09-12'",
      algorithm: :concurrently
  end
end
