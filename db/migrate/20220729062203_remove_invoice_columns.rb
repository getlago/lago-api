# frozen_string_literal: true

class RemoveInvoiceColumns < ActiveRecord::Migration[7.0]
  def up
    change_table :invoices, bulk: true do |t|
      t.remove :from_date
      t.remove :to_date
      t.remove :charges_from_date
    end
  end

  def down
  end
end
