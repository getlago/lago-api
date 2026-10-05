# frozen_string_literal: true

class AddIndexesToContractsInvoiceCustomSections < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :contracts_invoice_custom_sections, %i[contract_id invoice_custom_section_id],
      unique: true,
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_contracts_invoice_custom_sections_unique"

    add_index :contracts_invoice_custom_sections, :invoice_custom_section_id,
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_contracts_invoice_custom_sections_on_section_id"

    add_index :contracts_invoice_custom_sections, :organization_id,
      algorithm: :concurrently,
      if_not_exists: true,
      name: "index_contracts_invoice_custom_sections_on_organization_id"
  end
end
