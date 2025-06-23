# frozen_string_literal: true

class CreateInvoiceErrors < ActiveRecord::Migration[7.1]
  def change
    create_table :invoice_errors, id: :uuid do |t|
      t.text :backtrace
      t.json :invoice
      t.json :subscriptions
      t.json :error

      t.timestamps
    end
  end
end
