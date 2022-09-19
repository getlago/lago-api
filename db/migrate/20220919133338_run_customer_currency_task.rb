# frozen_string_literal: true

class RunCustomerCurrencyTask < ActiveRecord::Migration[7.0]
  def change
    # NOTE: Wait to ensure workers are loaded with the added tasks
    MigrationTaskJob.set(wait: 20.seconds).perform_later('customers:populate_currency')
  end
end
