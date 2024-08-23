# frozen_string_literal: true

class AddCurrencyToInvoices < ActiveRecord::Migration[7.0]
  def up
    add_column :invoices, :currency, :string

    safety_assured do
      execute <<-SQL
      UPDATE invoices
      SET currency = amount_currency
      SQL

      change_table :invoices, bulk: true do |t|
        t.remove :amount_currency
        t.remove :vat_amount_currency
        t.remove :total_amount_currency
        t.remove :credit_amount_currency
      end
    end
  end

  def down
    change_table :invoices, bulk: true do |t|
      t.string :amount_currency
      t.string :vat_amount_currency
      t.string :total_amount_currency
      t.string :credit_amount_currency
    end

    execute <<-SQL
      UPDATE invoices
      SET amount_currency = currency,
        vat_amount_currency = currency,
        total_amount_currency = currency,
        credit_amount_currency = currency
    SQL

    remove_column :invoices, :currency
  end
end
