# frozen_string_literal: true

class CreateInvoiceMetadata < ActiveRecord::Migration[7.0]
  def change
    create_table :invoice_metadata, id: :uuid do |t|
      t.references :invoice, type: :uuid, null: false, foreign_key: true, index: true

      t.string :key, null: false
      t.string :value, null: false

      t.timestamps

      t.index %w[invoice_id key], name: "index_invoice_metadata_on_invoice_id_and_key", unique: true
    end
  end
end
