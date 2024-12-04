# frozen_string_literal: true

class CreateAppliedInvoiceCustomSections < ActiveRecord::Migration[7.1]
  def change
    create_table :applied_invoice_custom_sections, id: :uuid do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :display_name
      t.string :details
      t.references :invoice, type: :uuid, null: false, foreign_key: true, index: true

      t.timestamps
    end
  end
end
