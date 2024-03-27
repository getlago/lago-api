# frozen_string_literal: true

class FixCurrencyOnInvoices < ActiveRecord::Migration[7.0]
  def change
    # NOTE: Wait to ensure workers are loaded with the added tasks
    MigrationTaskJob.set(wait: 20.seconds).perform_later("invoices:set_currency_to_fees")
  end
end
