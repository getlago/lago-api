# frozen_string_literal: true

class CreateInvoices < ActiveRecord::Migration[7.0]
  def change
    create_table :invoices, id: :uuid do |t|
      t.references :subscription, type: :uuid, foreign_key: true, idnex: true, null: false
      t.date :from_date, null: false
      t.date :to_date, null: false

      t.timestamps
    end
  end
end
