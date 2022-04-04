# frozen_string_literal: true

class CreateInvoices < ActiveRecord::Migration[7.0]
  def change
    create_table :invoices, id: :uuid do |t|
      t.references :subscription, type: :uuid, foreign_key: true, idnex: true, null: false
      t.timestamp :from_date
      t.timestamp :to_date

      t.timestamps
    end
  end
end
