# frozen_string_literal: true

class CreateInvoiceSubscriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :invoice_subscriptions, id: :uuid do |t|
      t.references :invoice, type: :uuid, index: true, null: false, foreign_key: true
      t.references :subscription, type: :uuid, index: true, null: false, foreign_key: true

      t.timestamps
    end
    remove_reference :invoices, :subscription, index: true, foreign_key: true
  end
end
