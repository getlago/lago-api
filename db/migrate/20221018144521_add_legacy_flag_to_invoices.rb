# frozen_string_literal: true

class AddLegacyFlagToInvoices < ActiveRecord::Migration[7.0]
  def up
    change_table :invoices, bulk: true do |t|
      t.boolean :legacy, null: false, default: false
      t.float :vat_rate
    end

    execute "UPDATE invoices SET legacy = 'true';"
    MigrationTaskJob.set(wait: 40.seconds).perform_later('invoices:fill_vat_rate')
  end

  def down
    change_table :invoices, bulk: true do |t|
      t.remove :legacy
      t.remove :vat_rate
    end
  end
end
