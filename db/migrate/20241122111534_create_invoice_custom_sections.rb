# frozen_string_literal: true

class CreateInvoiceCustomSections < ActiveRecord::Migration[7.1]
  def change
    create_table :invoice_custom_sections, id: :uuid do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.string :description
      t.string :display_name
      t.string :details
      t.references :organization, type: :uuid, null: false, foreign_key: true, index: true
      t.timestamp :deleted_at

      t.timestamps

      t.index %i[organization_id code], unique: true
      t.index %i[organization_id deleted_at]
    end
  end
end
