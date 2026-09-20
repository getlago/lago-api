# frozen_string_literal: true

class CreateContractsInvoiceCustomSections < ActiveRecord::Migration[8.0]
  def change
    create_table :contracts_invoice_custom_sections, id: :uuid do |t|
      t.references :organization, null: false, foreign_key: true, type: :uuid, index: true
      t.references :contract, null: false, foreign_key: true, type: :uuid, index: false
      t.references :invoice_custom_section, null: false, foreign_key: true, type: :uuid, index: true
      t.timestamps
      t.index %i[contract_id invoice_custom_section_id],
        unique: true,
        name: "index_contracts_invoice_custom_sections_unique"
    end

    add_column :contracts, :skip_invoice_custom_sections, :boolean, default: false, null: false
  end
end
