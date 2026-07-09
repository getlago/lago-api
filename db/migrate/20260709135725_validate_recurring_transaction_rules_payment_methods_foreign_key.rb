# frozen_string_literal: true

class ValidateRecurringTransactionRulesPaymentMethodsForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :recurring_transaction_rules, :payment_methods
  end
end
