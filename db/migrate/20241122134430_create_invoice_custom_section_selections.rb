# frozen_string_literal: true

class CreateInvoiceCustomSectionSelections < ActiveRecord::Migration[7.1]
  def change
    create_table :invoice_custom_section_selections, id: :uuid do |t|
      t.references :invoice_custom_section, type: :uuid, null: false, foreign_key: true
      t.references :organization, type: :uuid, null: true, foreign_key: true
      t.references :customer, type: :uuid, null: true, foreign_key: true

      t.timestamps
    end
  end
end
