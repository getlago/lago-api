# frozen_string_literal: true

class AddLegacyFlagToInvoices < ActiveRecord::Migration[7.0]
  def up
    safety_assured do
      change_table :invoices, bulk: true do |t|
        t.boolean :legacy, null: false, default: false
        t.float :vat_rate
      end

      execute "UPDATE invoices SET legacy = 'true';"

      execute <<-SQL
      UPDATE invoices
      SET vat_rate = ROUND((vat_amount_cents::decimal / amount_cents) * 100, 2)
      WHERE vat_rate IS NULL;
      SQL
    end
  end

  def down
    change_table :invoices, bulk: true do |t|
      t.remove :legacy
      t.remove :vat_rate
    end
  end
end
