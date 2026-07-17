# frozen_string_literal: true

class ValidatePaymentsPaymentMethodsForeignKey < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    validate_foreign_key :payments, :payment_methods
  end
end
