# frozen_string_literal: true

class CreateInvoiceConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :invoice_connections, id: :uuid do |t|
      t.references :organization, type: :uuid, null: false, foreign_key: true
      t.references :invoice,
        type: :uuid,
        null: false,
        foreign_key: true,
        index: false # covered by the unique (invoice_id, category) index below
      t.references :payment_provider_customer, type: :uuid, foreign_key: true
      t.references :integration_customer, type: :uuid, foreign_key: true

      t.enum :category, enum_type: :connection_category, null: false

      t.timestamps

      t.index [:invoice_id, :category], unique: true
    end
  end
end
