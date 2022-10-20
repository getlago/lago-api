# frozen_string_literal: true

class AddCreditAmountToInvoices < ActiveRecord::Migration[7.0]
  def up
    change_table :invoices, bulk: true do |t|
      t.bigint :credit_amount_cents, null: false, default: 0
      t.string :credit_amount_currency
    end

    MigrationTaskJob.set(wait: 40.seconds).perform_later('invoices:fill_credit_amount')
  end

  def down
    change_table :invoices, bulk: true do |t|
      t.remove :credit_amount_cents
      t.remove :credit_amount_currency
    end
  end
end
